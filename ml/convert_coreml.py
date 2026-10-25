#!/usr/bin/env python3
"""Convert a trained checkpoint to a Core ML package. Run this on a Mac."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    try:
        import coremltools as ct
        import torch
        from torch import nn
        from torchvision import models
    except ImportError:
        print("On a Mac: python3 -m pip install torch torchvision coremltools", file=sys.stderr)
        return 1

    blob = torch.load(args.checkpoint, map_location="cpu")
    labels = list(blob["labels"])
    model = models.mobilenet_v3_small(weights=None)
    model.classifier[-1] = nn.Linear(model.classifier[-1].in_features, len(labels))
    model.load_state_dict(blob["state_dict"])
    model.eval()

    example = torch.rand(1, 3, 224, 224)
    traced = torch.jit.trace(model, example)
    # ImageType scale/bias matches the Normalize() used in train_surface.py.
    mean = (0.485, 0.456, 0.406)
    std = (0.229, 0.224, 0.225)
    image = ct.ImageType(
        name="image",
        shape=example.shape,
        scale=1.0 / (255.0 * std[0]),
        bias=[-mean[c] / std[c] for c in range(3)],
        color_layout=ct.colorlayout.RGB,
    )
    mlmodel = ct.convert(
        traced,
        inputs=[image],
        classifier_config=ct.ClassifierConfig(labels),
    )
    mlmodel.short_description = (
        "Experimental road-surface classifier trained on RSCD (CC BY 4.0). "
        "Not validated on Arkansas roads. Labels: paved, unpaved, cant_tell."
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(args.output))
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
