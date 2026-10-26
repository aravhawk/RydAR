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
            seen[head] += int(keep.sum())
            correct[head] += int((pred[keep] == target[:, head][keep]).sum())
            for truth, guess, seq in zip(target[:, head].tolist(), pred.tolist(), batch_seq):
                if truth < 0:
                    continue
                confusion[head][truth, guess] += 1
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
    print(json.dumps({
        "frames": frames,
        "patches": patches,
        "material": report["heads"]["material"]["accuracy"],
        "friction": report["heads"]["friction"]["accuracy"],
        "uneven": report["heads"]["uneven"]["accuracy"],
        "wrote": str(out),
    }), flush=True)
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
