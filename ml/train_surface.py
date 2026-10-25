#!/usr/bin/env python3
"""Fine-tune one MobileNetV3-Small with three heads on RSCD.

Run this on a Daytona NVIDIA GPU. Create ML cannot run there, and it cannot
train three heads. Convert the checkpoint on a Mac with convert_coreml.py.

Heads, read from the RSCD folder name:
  material: paved, unpaved, cant_tell
  friction appearance: dry, wet, water, snow_ice, cant_tell
  unevenness: smooth, slight, severe, cant_tell

Snow and ice train the friction head only. Gravel and mud have no unevenness
label, so that head is masked. The phone may only use friction and unevenness
to speak earlier. Material is the only head that can change the screening
range, and only downward.

Do not point --data at the CC BY-NC million-image release or at StreetSurfaceVis.
Do not point --data at the 12 official test sequences.
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

from labels import FRICTION, MASK, MATERIAL, UNEVEN, cant_tell_target, parse_folder


def index_images(root: Path, cant_tell: Path | None) -> list[tuple[Path, str, tuple[int, int, int]]]:
    rows: list[tuple[Path, str, tuple[int, int, int]]] = []
    unknown: set[str] = set()
    for folder in sorted(p for p in root.iterdir() if p.is_dir()):
        target = parse_folder(folder.name)
        if target is None:
            unknown.add(folder.name)
            continue
        for image in folder.rglob("*"):
            if image.suffix.lower() in {".jpg", ".jpeg", ".png"}:
                rows.append((image, folder.name, target))
    if cant_tell is not None:
        target = cant_tell_target()
        for image in cant_tell.rglob("*"):
            if image.suffix.lower() in {".jpg", ".jpeg", ".png"}:
                rows.append((image, "cant_tell", target))
    if unknown:
        print("Skipped folders the parser did not recognize:", file=sys.stderr)
        for name in sorted(unknown):
            print(f"  {name}", file=sys.stderr)
    return rows


def split_rows(rows):
    """90/10 stratified by the original folder, so rare classes stay in both cuts."""
    random.seed(17)
    groups: dict[str, list] = {}
    for row in rows:
        groups.setdefault(row[1], []).append(row)
    train, val = [], []
    for group in groups.values():
        random.shuffle(group)
        cut = max(1, len(group) // 10) if len(group) > 1 else 0
        val.extend(group[:cut])
        train.extend(group[cut:])
    return train, val


def head_weights(rows, head: int, n_classes: int):
    import torch

    counts = [0] * n_classes
    for row in rows:
        label = row[2][head]
        if label >= 0:
            counts[label] += 1
    total = sum(counts)
    present = sum(1 for c in counts if c)
    weights = [0.0 if c == 0 else total / (present * c) for c in counts]
    return torch.tensor(weights, dtype=torch.float)


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
        from torchvision import transforms
        from PIL import Image
        from roadnet import RoadNet
    except ImportError:
        print("Install torch, torchvision, and pillow on the GPU machine.", file=sys.stderr)
        return 1

    rows = index_images(args.data, args.cant_tell)
    train_rows, val_rows = split_rows(rows)
    print(json.dumps({
        "images": len(rows),
        "folders": len({row[1] for row in rows}),
        "train": len(train_rows),
        "validation": len(val_rows),
        "test": "RSCD 12 sequences, 2880 patches, not loaded here",
        "validation_note": "early stopping only; neighboring frames can leak; do not quote",
    }))
    materials = {row[2][0] for row in train_rows}
    if MATERIAL.index("paved") not in materials or MATERIAL.index("unpaved") not in materials:
        print("Need both paved and unpaved images. Check the folder names.", file=sys.stderr)
        return 1

    class Roads(Dataset):
        def __init__(self, items, transform):
            self.items = items
            self.transform = transform

        def __len__(self):
            return len(self.items)

        def __getitem__(self, index):
            path, _folder, target = self.items[index]
            image = Image.open(path).convert("RGB")
            return self.transform(image), torch.tensor(target, dtype=torch.long)

    train_transform = transforms.Compose(
        [
            transforms.Resize((224, 224)),
            transforms.ColorJitter(brightness=0.4, contrast=0.3, saturation=0.2),
            transforms.GaussianBlur(kernel_size=3, sigma=(0.1, 1.5)),
            transforms.ToTensor(),
            transforms.Normalize(mean=(0.485, 0.456, 0.406), std=(0.229, 0.224, 0.225)),
        ]
    )
    eval_transform = transforms.Compose(
        [
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(mean=(0.485, 0.456, 0.406), std=(0.229, 0.224, 0.225)),
        ]
    )
    train_loader = DataLoader(
        Roads(train_rows, train_transform), batch_size=args.batch, shuffle=True, num_workers=2
    )
    val_loader = DataLoader(
        Roads(val_rows, eval_transform), batch_size=args.batch, shuffle=False, num_workers=2
    ) if val_rows else None

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    if device.type != "cuda":
        print("No CUDA device. Run this on a Daytona NVIDIA GPU.", file=sys.stderr)
    model = RoadNet(pretrained=True).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)
    losses = [
        nn.CrossEntropyLoss(weight=head_weights(train_rows, 0, len(MATERIAL)).to(device), ignore_index=MASK),
        nn.CrossEntropyLoss(weight=head_weights(train_rows, 1, len(FRICTION)).to(device), ignore_index=MASK),
        nn.CrossEntropyLoss(weight=head_weights(train_rows, 2, len(UNEVEN)).to(device), ignore_index=MASK),
    ]

    def masked_loss(logits, target, loss_fn):
        if bool((target >= 0).any()):
            return loss_fn(logits, target)
        return logits.sum() * 0

    def evaluate(loader) -> dict[str, float]:
        model.eval()
        correct = [0, 0, 0]
        seen = [0, 0, 0]
        with torch.no_grad():
            for images, target in loader:
                images = images.to(device)
                target = target.to(device)
                heads = model(images)
                for i, logits in enumerate(heads):
                    keep = target[:, i] >= 0
                    seen[i] += int(keep.sum())
                    if bool(keep.any()):
                        pred = logits.argmax(dim=1)
                        correct[i] += int((pred[keep] == target[:, i][keep]).sum())
        names = ("material", "friction", "uneven")
        return {names[i]: correct[i] / seen[i] for i in range(3) if seen[i]}

    best_score = -1.0
    best_state = None
    history = []
    for epoch in range(args.epochs):
        model.train()
        total = 0.0
        seen = 0
        for images, target in train_loader:
            images = images.to(device)
            target = target.to(device)
            optimizer.zero_grad()
            heads = model(images)
            loss = sum(masked_loss(heads[i], target[:, i], losses[i]) for i in range(3))
            loss.backward()
            optimizer.step()
            total += float(loss) * images.size(0)
            seen += images.size(0)
        row = {"epoch": epoch + 1, "loss": total / max(seen, 1)}
        if val_loader is not None:
            scores = evaluate(val_loader)
            row["validation_accuracy_do_not_quote"] = scores
            score = sum(scores.values()) / max(len(scores), 1)
            if score > best_score:
                best_score = score
                best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
        history.append(row)
        print(json.dumps(row))

    if best_state is not None:
        model.load_state_dict(best_state)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    blob = {
        "state_dict": model.state_dict(),
        "material_labels": list(MATERIAL),
        "friction_labels": list(FRICTION),
        "uneven_labels": list(UNEVEN),
    }
    torch.save(blob, args.out)
    metrics = {
        "heads": {
            "material": list(MATERIAL),
            "friction": list(FRICTION),
            "uneven": list(UNEVEN),
        },
        "images": len(rows),
        "train": len(train_rows),
        "validation": len(val_rows),
        "epochs": history,
        "checkpoint": str(args.out),
        "quoted_test": "Run the 12 RSCD sequences once, after this file exists. Do not quote validation accuracy.",
    }
    args.out.with_suffix(".metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
    print(f"Wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
