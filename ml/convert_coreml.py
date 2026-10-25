#!/usr/bin/env python3
"""Convert a trained three-head checkpoint to a Core ML package. Run this on a Mac."""

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
        from roadnet import RoadNet
    except ImportError:
        print("On a Mac: python3 -m pip install torch torchvision coremltools", file=sys.stderr)
        return 1

    blob = torch.load(args.checkpoint, map_location="cpu")
    model = RoadNet(pretrained=False)
    model.load_state_dict(blob["state_dict"])
    model.eval()

    class SoftmaxHeads(torch.nn.Module):
        def __init__(self, net: RoadNet) -> None:
            super().__init__()
            self.net = net

        def forward(self, x: torch.Tensor):
            material, friction, uneven = self.net(x)
            return material.softmax(dim=1), friction.softmax(dim=1), uneven.softmax(dim=1)

    example = torch.rand(1, 3, 224, 224)
    traced = torch.jit.trace(SoftmaxHeads(model), example)
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
        outputs=[
            ct.TensorType(name="material"),
            ct.TensorType(name="friction"),
            ct.TensorType(name="uneven"),
        ],
    )
    mlmodel.short_description = (
        "Experimental road-state model trained on RSCD (CC BY 4.0). "
        "Not validated on Arkansas roads. Material can only lower the screening "
        "assumption. Friction appearance and unevenness can only move a warning earlier."
    )
    mlmodel.user_defined_metadata["material_labels"] = ",".join(blob["material_labels"])
    mlmodel.user_defined_metadata["friction_labels"] = ",".join(blob["friction_labels"])
    mlmodel.user_defined_metadata["uneven_labels"] = ",".join(blob["uneven_labels"])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(args.output))
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
