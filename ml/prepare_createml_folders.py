#!/usr/bin/env python3
"""Sort RSCD class folders into paved, unpaved, and cant_tell for Create ML.

Makes symlinks. Does not copy the JPEGs and does not train.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def collapse(folder_name: str) -> str | None:
    name = folder_name.lower()
    if "snow" in name or "ice" in name:
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--cant-tell", type=Path, default=None)
    parser.add_argument("--out", type=Path, default=Path("ml/data/createml"))
    args = parser.parse_args()

    for label in ("paved", "unpaved", "cant_tell"):
        (args.out / label).mkdir(parents=True, exist_ok=True)

    skipped: list[str] = []
    counts = {"paved": 0, "unpaved": 0, "cant_tell": 0}
    for folder in sorted(path for path in args.data.iterdir() if path.is_dir()):
        label = collapse(folder.name)
        if label is None:
            skipped.append(folder.name)
            continue
        for image in folder.rglob("*"):
            if image.suffix.lower() not in {".jpg", ".jpeg", ".png"}:
                continue
            dest = args.out / label / f"{folder.name}__{image.name}"
            if not dest.exists():
                dest.symlink_to(image.resolve())
            counts[label] += 1

    if args.cant_tell is not None:
        for image in args.cant_tell.rglob("*"):
            if image.suffix.lower() not in {".jpg", ".jpeg", ".png"}:
                continue
            dest = args.out / "cant_tell" / image.name
            if not dest.exists():
                dest.symlink_to(image.resolve())
            counts["cant_tell"] += 1

    print(counts)
    if skipped:
        print("Skipped folders:", file=sys.stderr)
        for name in skipped:
            print(f"  {name}", file=sys.stderr)
    if counts["paved"] == 0 or counts["unpaved"] == 0:
        print("Need both paved and unpaved images.", file=sys.stderr)
        return 1
    print(f"Open {args.out} in Create ML.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
