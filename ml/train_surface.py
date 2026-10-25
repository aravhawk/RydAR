#!/usr/bin/env python3
"""Fine-tune MobileNetV3-Small on RSCD (Mendeley, CC BY 4.0).

Run this on a Daytona NVIDIA GPU. Create ML cannot run there. Convert the
checkpoint on a Mac with convert_coreml.py. The phone only runs that file.

The shipped model uses only this dataset. Do not point --data at the
CC BY-NC million-image release or at StreetSurfaceVis.
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path


LABELS = ("paved", "unpaved", "cant_tell")


def collapse(folder_name: str) -> str | None:
    name = folder_name.lower()
    if any(word in name for word in ("snow", "ice")):
        return None
    paved = "asphalt" in name or "concrete" in name
    unpaved = "gravel" in name or "mud" in name
    if paved and unpaved:
        return None
    if paved:
        return "paved"
    if unpaved:
        return "unpaved"
    return None


def index_images(root: Path, cant_tell: Path | None) -> list[tuple[Path, str]]:
    rows: list[tuple[Path, str]] = []
    unknown: set[str] = set()
    for folder in sorted(p for p in root.iterdir() if p.is_dir()):
        label = collapse(folder.name)
        if label is None:
            unknown.add(folder.name)
            continue
        for image in folder.rglob("*"):
            if image.suffix.lower() in {".jpg", ".jpeg", ".png"}:
                rows.append((image, label))
    if cant_tell is not None:
        for image in cant_tell.rglob("*"):
            if image.suffix.lower() in {".jpg", ".jpeg", ".png"}:
                rows.append((image, "cant_tell"))
    if unknown:
        print("Skipped folders (not paved, unpaved, or snow/ice):", file=sys.stderr)
        for name in sorted(unknown):
            print(f"  {name}", file=sys.stderr)
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, required=True, help="RSCD train-set directory")
    parser.add_argument("--cant-tell", type=Path, default=None)
    parser.add_argument("--epochs", type=int, default=5)
    parser.add_argument("--batch", type=int, default=64)
    parser.add_argument("--out", type=Path, default=Path("ml/runs/roadsurface.pt"))
    args = parser.parse_args()

    try:
        import torch
        from torch import nn
        from torch.utils.data import DataLoader, Dataset
        from torchvision import models, transforms
        from PIL import Image
    except ImportError:
        print("Install torch, torchvision, and pillow on the GPU machine.", file=sys.stderr)
        return 1

    rows = index_images(args.data, args.cant_tell)
    counts = {label: sum(1 for _, y in rows if y == label) for label in LABELS}
    # 10% stratified holdout for early stopping. The official test sequences
    # are not in the train-set folder and must not be passed as --data.
    random.seed(17)
    train_rows = []
    val_rows = []
    for label in LABELS:
        group = [row for row in rows if row[1] == label]
        random.shuffle(group)
        cut = max(1, len(group) // 10) if group else 0
        val_rows.extend(group[:cut])
        train_rows.extend(group[cut:])
    print(json.dumps({
        "images": counts,
        "train": len(train_rows),
        "validation": len(val_rows),
        "test": "RSCD 12 sequences, 2880 patches, not loaded here",
    }))
    if counts["paved"] == 0 or counts["unpaved"] == 0:
        print("Need both paved and unpaved images. Check the folder names.", file=sys.stderr)
        return 1

    class Roads(Dataset):
        def __init__(self, items, transform):
            self.items = items
            self.transform = transform

        def __len__(self):
            return len(self.items)

        def __getitem__(self, index):
            path, label = self.items[index]
            image = Image.open(path).convert("RGB")
            return self.transform(image), LABELS.index(label)

    transform = transforms.Compose(
        [
            transforms.Resize((224, 224)),
            transforms.ColorJitter(brightness=0.4, contrast=0.3, saturation=0.2),
            transforms.GaussianBlur(kernel_size=3, sigma=(0.1, 1.5)),
            transforms.ToTensor(),
            transforms.Normalize(mean=(0.485, 0.456, 0.406), std=(0.229, 0.224, 0.225)),
        ]
    )
    loader = DataLoader(Roads(train_rows, transform), batch_size=args.batch, shuffle=True, num_workers=2)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    if device.type != "cuda":
        print("No CUDA device. Run this on a Daytona NVIDIA GPU.", file=sys.stderr)
    model = models.mobilenet_v3_small(weights=models.MobileNet_V3_Small_Weights.DEFAULT)
    model.classifier[-1] = nn.Linear(model.classifier[-1].in_features, len(LABELS))
    model = model.to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)
    loss_fn = nn.CrossEntropyLoss()

    model.train()
    for epoch in range(args.epochs):
        total = 0.0
        seen = 0
        correct = 0
        for images, labels in loader:
            images = images.to(device)
            labels = labels.to(device)
            optimizer.zero_grad()
            logits = model(images)
            loss = loss_fn(logits, labels)
            loss.backward()
            optimizer.step()
            total += float(loss) * images.size(0)
            seen += images.size(0)
            correct += int((logits.argmax(dim=1) == labels).sum())
        print(json.dumps({"epoch": epoch + 1, "loss": total / max(seen, 1), "train_acc": correct / max(seen, 1)}))

    args.out.parent.mkdir(parents=True, exist_ok=True)
    torch.save({"state_dict": model.state_dict(), "labels": list(LABELS)}, args.out)
    metrics = {"labels": list(LABELS), "images": counts, "epochs": args.epochs, "checkpoint": str(args.out)}
    args.out.with_suffix(".metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
    print(f"Wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
