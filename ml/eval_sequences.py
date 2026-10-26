#!/usr/bin/env python3
"""Score the shipped checkpoint on the 12 RSCD sequences it never trained on.

The sequences are the test-set folder in the CC BY 4.0 Mendeley zip
(DOI 10.17632/w86hvkrzc5), described in Data in Brief 10.1016/j.dib.2022.108483.
Each sequence is 30 frames of 1920x1080. Eight 240x360 patches are labeled
per frame. This is not the random validation split, and it is not an
Arkansas road test.

Do not point this at the million-image RSXD release.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.request
import zlib
import struct
from pathlib import Path

from labels import FRICTION, MASK, MATERIAL, UNEVEN, parse_folder

# Upper-left corners, width then height, from the data article.
PATCHES = (
    (480, 200),
    (720, 200),
    (960, 200),
    (1200, 200),
    (480, 560),
    (720, 560),
    (960, 560),
    (1200, 560),
)
CROP_W = 240
CROP_H = 360
ZIP_URL = (
    "https://data.mendeley.com/public-files/datasets/w86hvkrzc5/files/"
    "ece1801c-6c4c-4150-b7da-9bc78270b3bd/file_downloaded"
)
# The test-set is stored at the front of dataset(v2).zip. The last test
# member ends just past this offset; the training images start after it.
ZIP_PREFIX = 321_000_000


def download_prefix(dest: Path) -> None:
    if dest.exists() and dest.stat().st_size >= ZIP_PREFIX:
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(
        ZIP_URL,
        headers={"Range": f"bytes=0-{ZIP_PREFIX - 1}", "User-Agent": "Mozilla/5.0"},
    )
    with urllib.request.urlopen(request, timeout=120) as response, dest.open("wb") as out:
        status = getattr(response, "status", 200)
        length = int(response.headers.get("Content-Length", "0") or 0)
        if status == 200 and length > ZIP_PREFIX:
            raise SystemExit("The dataset server ignored the range request.")
        remaining = ZIP_PREFIX
        while remaining:
            chunk = response.read(min(1 << 20, remaining))
            if not chunk:
                break
            out.write(chunk)
            remaining -= len(chunk)
    print(json.dumps({"zip_prefix_bytes": dest.stat().st_size}), flush=True)


def extract_test_set(blob: bytes, dest: Path) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    offset = 0
    written = 0
    while offset + 30 <= len(blob) and blob[offset : offset + 4] == b"PK\x03\x04":
        method, = struct.unpack_from("<H", blob, offset + 8)
        comp, _, name_len, extra_len = struct.unpack_from("<IIHH", blob, offset + 18)
        name = blob[offset + 30 : offset + 30 + name_len].decode("utf-8")
        data_at = offset + 30 + name_len + extra_len
        nxt = data_at + comp
        if nxt > len(blob):
            break
        if name.startswith("dataset/test-set/") and not name.endswith("/"):
            raw = blob[data_at:nxt]
            body = raw if method == 0 else zlib.decompress(raw, -15)
            path = dest / name.split("/", 2)[-1]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(body)
            written += 1
        offset = nxt
        if "/train-set/" in name:
            break
    return written


def roc_auc(y_true, y_score) -> float | None:
    """ROC AUC by the Mann–Whitney rank formula. Ties get the average rank."""
    y_true = [int(value) for value in y_true]
    y_score = [float(value) for value in y_score]
    n_pos = sum(y_true)
    n_neg = len(y_true) - n_pos
    if n_pos == 0 or n_neg == 0:
        return None
    order = sorted(range(len(y_score)), key=lambda index: y_score[index])
    ranks = [0.0] * len(y_score)
    start = 0
    while start < len(order):
        end = start
        while end + 1 < len(order) and y_score[order[end + 1]] == y_score[order[start]]:
            end += 1
        average = (start + 1 + end + 1) / 2.0
        for cursor in range(start, end + 1):
            ranks[order[cursor]] = average
        start = end + 1
    sum_pos = sum(rank for rank, label in zip(ranks, y_true) if label == 1)
    return (sum_pos - n_pos * (n_pos + 1) / 2.0) / (n_pos * n_neg)


def aurc(confidence, correct) -> float | None:
    """Area under the risk-coverage curve. Lower is better.

    Samples are ordered from most confident to least. At each coverage the
    risk is the error rate among the samples kept so far. The reported area
    is the mean of those risks, which is the equal-step integral from 0 to 1.
    """
    paired = sorted(zip(confidence, correct), key=lambda item: -float(item[0]))
    if not paired:
        return None
    risks = []
    errors = 0
    for index, (_, is_correct) in enumerate(paired, start=1):
        errors += 0 if is_correct else 1
        risks.append(errors / index)
    return sum(risks) / len(risks)


def aurc_optimal(n_correct: int, total: int) -> float | None:
    """AURC if every correct call were ranked above every incorrect call."""
    if total <= 0:
        return None
    risks = [max(0, index - n_correct) / index for index in range(1, total + 1)]
    return sum(risks) / len(risks)


def summarize_head(truths: list[int], probabilities: list[list[float]], class_names: tuple[str, ...]) -> dict:
    """Accuracy, precision, recall, one-vs-rest AUC, and AURC at the argmax point."""
    count = len(truths)
    if count == 0:
        return {}
    predicted = [max(range(len(row)), key=lambda index: row[index]) for row in probabilities]
    correct_flags = [guess == truth for guess, truth in zip(predicted, truths)]
    confidence = [max(row) for row in probabilities]
    classes = []
    precisions = []
    recalls = []
    aucs = []
    for index, name in enumerate(class_names):
        support = sum(truth == index for truth in truths)
        called = sum(guess == index for guess in predicted)
        hits = sum(truth == index and guess == index for truth, guess in zip(truths, predicted))
        precision = (hits / called) if called else (0.0 if support else None)
        recall = (hits / support) if support else None
        if support:
            precisions.append(0.0 if precision is None else precision)
            recalls.append(0.0 if recall is None else recall)
        auc = roc_auc(
            [1 if truth == index else 0 for truth in truths],
            [row[index] for row in probabilities],
        )
        if auc is not None:
            aucs.append(auc)
        classes.append({
            "name": name,
            "support": support,
            "predicted": called,
            "hits": hits,
            "precision": precision,
            "recall": recall,
            "ovr_auc": auc,
        })
    n_correct = sum(correct_flags)
    return {
        "accuracy": n_correct / count,
        "macro_precision": sum(precisions) / len(precisions) if precisions else None,
        "macro_recall": sum(recalls) / len(recalls) if recalls else None,
        "macro_ovr_auc": sum(aucs) / len(aucs) if aucs else None,
        "aurc": aurc(confidence, correct_flags),
        "aurc_optimal": aurc_optimal(n_correct, count),
        "classes_in_macro": len(precisions),
        "classes_in_auc": len(aucs),
        "per_class": classes,
        "definitions": {
            "accuracy": "Argmax matches the label, over patches whose label is not masked.",
            "macro_precision": "Unweighted mean of per-class precision. A class with no labeled patches is left out. A class that is never predicted scores 0.",
            "macro_recall": "Unweighted mean of per-class recall over classes that have at least one labeled patch.",
            "macro_ovr_auc": "Unweighted mean of one-versus-rest ROC AUC. A class with no positive or no negative patches is left out. Higher is better.",
            "aurc": "Area under the risk-coverage curve from max-softmax confidence. Lower is better. aurc_optimal is the same area if every correct call were ranked first.",
        },
    }


def labels_for(text: str) -> list[tuple[int, int, int]]:
    tokens = text.split()
    if len(tokens) != 8:
        raise ValueError(f"expected 8 labels, got {len(tokens)}: {text!r}")
    parsed = []
    for token in tokens:
        target = parse_folder(token)
        if target is None:
            raise ValueError(f"unparsed label {token!r}")
        parsed.append(target)
    return parsed


def score(root: Path, checkpoint: Path, out: Path) -> dict:
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
    blob = torch.load(checkpoint, map_location="cpu")
    model = RoadNet(pretrained=False)
    model.load_state_dict(blob["state_dict"])
    model.to(device).eval()

    names = ("material", "friction", "uneven")
    label_names = (MATERIAL, FRICTION, UNEVEN)
    correct = [0, 0, 0]
    seen = [0, 0, 0]
    confusion = [torch.zeros(len(label_names[i]), len(label_names[i]), dtype=torch.long) for i in range(3)]
    stored_truth: list[list[int]] = [[], [], []]
    stored_prob: list[list[list[float]]] = [[], [], []]
    per_sequence: dict[str, dict] = {}
    frames = 0
    patches = 0

    frame_paths = sorted(root.rglob("*.jpg"))
    if not frame_paths:
        raise SystemExit(f"No frames under {root}")

    batch_images = []
    batch_targets = []
    batch_seq = []

    def flush() -> None:
        if not batch_images:
            return
        images = torch.stack(batch_images).to(device)
        target = torch.tensor(batch_targets, dtype=torch.long, device=device)
        with torch.no_grad():
            heads = model(images)
        for head, logits in enumerate(heads):
            keep = target[:, head] >= 0
            if not bool(keep.any()):
                continue
            pred = logits.argmax(dim=1)
            probability = torch.softmax(logits, dim=1)
            seen[head] += int(keep.sum())
            correct[head] += int((pred[keep] == target[:, head][keep]).sum())
            for truth, guess, scores, seq in zip(
                target[:, head].tolist(), pred.tolist(), probability.tolist(), batch_seq
            ):
                if truth < 0:
                    continue
                confusion[head][truth, guess] += 1
                stored_truth[head].append(truth)
                stored_prob[head].append(scores)
                row = per_sequence[seq][names[head]]
                row["seen"] += 1
                row["correct"] += int(guess == truth)
        batch_images.clear()
        batch_targets.clear()
        batch_seq.clear()

    for path in frame_paths:
        text_path = path.with_suffix(".txt")
        targets = labels_for(text_path.read_text())
        image = Image.open(path).convert("RGB")
        if image.size != (1920, 1080):
            raise SystemExit(f"{path.name} is {image.size}, expected 1920x1080")
        seq = path.parent.name
        per_sequence.setdefault(
            seq,
            {name: {"correct": 0, "seen": 0} for name in names},
        )
        frames += 1
        for (x, y), target in zip(PATCHES, targets):
            crop = image.crop((x, y, x + CROP_W, y + CROP_H))
            batch_images.append(transform(crop))
            batch_targets.append(target)
            batch_seq.append(seq)
            patches += 1
            if len(batch_images) == 64:
                flush()
    flush()

    def rates(head: int) -> dict:
        matrix = confusion[head]
        result = {}
        for i, name in enumerate(label_names[head]):
            total = int(matrix[i].sum())
            result[name] = {
                "support": total,
                "recall": (int(matrix[i, i]) / total) if total else None,
            }
        return result

    report = {
        "checkpoint": str(checkpoint),
        "what_this_is": (
            "Held-out RSCD test-set: 12 sequences, 30 frames, 8 patches. "
            "The training run did not load these frames. Beijing roads, not Arkansas. "
            "Do not quote the random validation split as this number."
        ),
        "device": str(device),
        "frames": frames,
        "patches": patches,
        "heads": {
            names[i]: {
                "correct": correct[i],
                "seen": seen[i],
                "accuracy": (correct[i] / seen[i]) if seen[i] else None,
                "recall_by_class": rates(i),
                "operating_point": summarize_head(stored_truth[i], stored_prob[i], label_names[i]),
            }
            for i in range(3)
        },
        "sequences": {
            seq: {
                name: {
                    "correct": per_sequence[seq][name]["correct"],
                    "seen": per_sequence[seq][name]["seen"],
                    "accuracy": (
                        per_sequence[seq][name]["correct"] / per_sequence[seq][name]["seen"]
                        if per_sequence[seq][name]["seen"]
                        else None
                    ),
                }
                for name in names
            }
            for seq in sorted(per_sequence, key=lambda item: int(item))
        },
        "phone_uses": {
            "material_can_only_lower_paved_to_unpaved": True,
            "water_or_snow_and_severe_only_move_the_warning_earlier": True,
            "masked_label": MASK,
        },
    }
    # Decisions the phone can act on. Argmax, one patch, no six-frame vote.
    material = confusion[0]
    paved, unpaved = MATERIAL.index("paved"), MATERIAL.index("unpaved")
    friction = confusion[1]
    dry, water, snow = FRICTION.index("dry"), FRICTION.index("water"), FRICTION.index("snow_ice")
    uneven = confusion[2]
    severe = UNEVEN.index("severe")
    paved_n = int(material[paved].sum())
    unpaved_n = int(material[unpaved].sum())
    report["phone_decisions_argmax"] = {
        "true_paved_called_unpaved": int(material[paved, unpaved]),
        "true_paved": paved_n,
        "true_unpaved_called_paved": int(material[unpaved, paved]),
        "true_unpaved": unpaved_n,
        "true_dry_called_water_or_snow": int(friction[dry, water] + friction[dry, snow]),
        "true_dry": int(friction[dry].sum()),
        "true_water_called_water": int(friction[water, water]),
        "true_water": int(friction[water].sum()),
        "true_snow_ice_called_snow_ice": int(friction[snow, snow]),
        "true_snow_ice": int(friction[snow].sum()),
        "true_severe_called_severe": int(uneven[severe, severe]),
        "true_severe": int(uneven[severe].sum()),
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n")
    summary = {}
    for name in names:
        point = report["heads"][name]["operating_point"]
        summary[name] = {
            "accuracy": point.get("accuracy"),
            "macro_precision": point.get("macro_precision"),
            "macro_recall": point.get("macro_recall"),
            "macro_ovr_auc": point.get("macro_ovr_auc"),
            "aurc": point.get("aurc"),
            "aurc_optimal": point.get("aurc_optimal"),
        }
    print(json.dumps({"frames": frames, "patches": patches, "heads": summary, "wrote": str(out)}), flush=True)
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--root", type=Path, default=None, help="Extracted test-set directory")
    parser.add_argument("--fetch", action="store_true", help="Download the zip prefix and extract test-set")
    parser.add_argument("--cache", type=Path, default=Path("/tmp/rscd-prefix.zip"))
    parser.add_argument("--out", type=Path, default=Path("ml/sequence-test.json"))
    args = parser.parse_args()
    root = args.root
    if args.fetch:
        download_prefix(args.cache)
        root = root or Path("/tmp/rscd-test-set")
        written = extract_test_set(args.cache.read_bytes(), root)
        print(json.dumps({"extracted": written, "root": str(root)}), flush=True)
    if root is None:
        print("Pass --root or --fetch.", file=sys.stderr)
        return 1
    score(root, args.checkpoint, args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
