#!/usr/bin/env python3
"""Replay the phone's camera gate on the 12 held-out sequences.

The phone does not classify the eight small patches. It crops the lower center
of the frame, then keeps a head only when 4 of the last 6 frames agree and the
weakest of those votes clears a confidence threshold. This script runs that
rule on the full 1920x1080 frames. The label for a frame is the majority of
the four lower patches, which sit in that crop. It does not retrain anything.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

from eval_sequences import CROP_H, PATCHES, download_prefix, extract_test_set, labels_for
from labels import FRICTION, MATERIAL, UNEVEN

# DashCrop: bottom 45 percent, center 50 percent, image origin at the top left.
PHONE_CROP = (480, 594, 1440, 1080)
LOWER_PATCHES = PATCHES[4:]
THRESHOLDS = (0.5, 0.6, 0.7, 0.8, 0.9)


def majority(labels: list[int]) -> int | None:
    usable = [label for label in labels if label >= 0]
    if not usable:
        return None
    counts = Counter(usable)
    winner, votes = counts.most_common(1)[0]
    if votes < (len(usable) + 1) // 2 or list(counts.values()).count(votes) > 1:
        return None
    return winner


def phone_accepts(votes: list[tuple[int, float]], threshold: float) -> int | None:
    """Same rule as DashConsensus: the most common label in a full window of 6."""
    if len(votes) < 6:
        return None
    grouped: dict[int, list[float]] = {}
    for label, confidence in votes:
        grouped.setdefault(label, []).append(confidence)
    winner = max(grouped.items(), key=lambda item: len(item[1]))
    if len(winner[1]) < 4:
        return None
    if min(winner[1]) < threshold:
        return None
    return winner[0]


def binary_counts(truths: list[int | None], calls: list[int | None], positive: set[int]) -> dict:
    decided = [(truth, call) for truth, call in zip(truths, calls) if truth is not None]
    acted = [(truth, call) for truth, call in decided if call in positive]
    should = [(truth, call) for truth, call in decided if truth in positive]
    hits = sum(1 for truth, call in acted if truth in positive)
    caught = sum(1 for truth, call in should if call in positive)
    return {
        "windows": len(decided),
        "acted": len(acted),
        "should_act": len(should),
        "precision": (hits / len(acted)) if acted else None,
        "recall": (caught / len(should)) if should else None,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--fetch", action="store_true")
    parser.add_argument("--cache", type=Path, default=Path("/tmp/rscd-prefix.zip"))
    parser.add_argument("--root", type=Path, default=Path("/tmp/rscd-test-set"))
    parser.add_argument("--out", type=Path, default=Path("ml/phone-gate.json"))
    args = parser.parse_args()
    root = args.root
    if args.fetch:
        download_prefix(args.cache)
        written = extract_test_set(args.cache.read_bytes(), root)
        print(json.dumps({"extracted": written}), flush=True)

    import torch
    from PIL import Image
    from torchvision import transforms

    from roadnet import IMAGENET_MEAN, IMAGENET_STD, RoadNet

    transform = transforms.Compose(
        [
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(mean=IMAGENET_MEAN, std=IMAGENET_STD),
        ]
    )
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    blob = torch.load(args.checkpoint, map_location="cpu")
    model = RoadNet(pretrained=False)
    model.load_state_dict(blob["state_dict"])
    model.to(device).eval()

    sequences: dict[str, list[dict]] = {}
    batch_images = []
    batch_meta = []

    def flush() -> None:
        if not batch_images:
            return
        images = torch.stack(batch_images).to(device)
        with torch.no_grad():
            heads = model(images)
        probabilities = [torch.softmax(logits, dim=1).tolist() for logits in heads]
        for index, meta in enumerate(batch_meta):
            meta["probs"] = [probabilities[head][index] for head in range(3)]
            sequences[meta["seq"]].append(meta)
        batch_images.clear()
        batch_meta.clear()

    for path in sorted(root.rglob("*.jpg")):
        targets = labels_for(path.with_suffix(".txt").read_text())
        lower = targets[4:]
        image = Image.open(path).convert("RGB")
        if image.size != (1920, 1080):
            raise SystemExit(f"{path.name} is {image.size}")
        batch_images.append(transform(image.crop(PHONE_CROP)))
        batch_meta.append({
            "seq": path.parent.name,
            "name": path.name,
            "truth": [
                majority([target[0] for target in lower]),
                majority([target[1] for target in lower]),
                majority([target[2] for target in lower]),
            ],
        })
        sequences.setdefault(path.parent.name, [])
        if len(batch_images) == 32:
            flush()
    flush()

    names = ("material", "friction", "uneven")
    label_sets = (MATERIAL, FRICTION, UNEVEN)
    positives = (
        {MATERIAL.index("unpaved")},
        {FRICTION.index("water"), FRICTION.index("snow_ice")},
        {UNEVEN.index("severe")},
    )
    report: dict = {
        "what_this_is": (
            "Phone crop and the 4-of-6 gate on the 12 held-out sequences. "
            "Not an Arkansas drive. Do not say these in the video or the app."
        ),
        "crop": {"left": 480, "top": 594, "right": 1440, "bottom": 1080},
        "gate": "4 of the last 6 frames, weakest vote at or above the threshold",
        "device": str(device),
        "thresholds": {},
    }
    single_correct = [0, 0, 0]
    single_seen = [0, 0, 0]
    for frames in sequences.values():
        frames.sort(key=lambda item: item["name"])
        for frame in frames:
            for head in range(3):
                truth = frame["truth"][head]
                if truth is None or truth < 0:
                    continue
                guess = max(range(len(frame["probs"][head])), key=lambda i: frame["probs"][head][i])
                single_seen[head] += 1
                single_correct[head] += int(guess == truth)
    report["single_frame_phone_crop"] = {
        names[head]: {
            "correct": single_correct[head],
            "seen": single_seen[head],
            "accuracy": (single_correct[head] / single_seen[head]) if single_seen[head] else None,
        }
        for head in range(3)
    }

    for threshold in THRESHOLDS:
        per_head = {}
        for head, positive in enumerate(positives):
            truths: list[int | None] = []
            calls: list[int | None] = []
            for frames in sequences.values():
                window: list[tuple[int, float]] = []
                for frame in frames:
                    scores = frame["probs"][head]
                    guess = max(range(len(scores)), key=lambda i: scores[i])
                    window.append((guess, scores[guess]))
                    if len(window) > 6:
                        window = window[-6:]
                    truths.append(frame["truth"][head])
                    calls.append(phone_accepts(window, threshold))
            per_head[names[head]] = {
                "positive": [label_sets[head][index] for index in sorted(positive)],
                **binary_counts(truths, calls, positive),
            }
        report["thresholds"][str(threshold)] = per_head

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({
        "single_frame": report["single_frame_phone_crop"],
        "at_0.8": report["thresholds"]["0.8"],
        "at_0.9": report["thresholds"]["0.9"],
        "wrote": str(args.out),
    }), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
