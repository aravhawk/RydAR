"""One MobileNetV4-Conv-Small trunk, three heads. Train and convert both import this.

Conv-Small, not the hybrid and not the large. The hybrid attention blocks are a
worse bet for the Neural Engine. The large model is trained at 384 and is more
than this camera needs. ImageNet top-1 for this checkpoint is about 73.8% at
224, against about 67.7% for torchvision MobileNetV3-Small, at a size the
iPhone 13 ran in well under a millisecond in the MobileNetV4 paper.
"""

from __future__ import annotations

import torch
from torch import nn

from labels import FRICTION, MATERIAL, UNEVEN

BACKBONE = "mobilenetv4_conv_small.e2400_r224_in1k"
IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)


class RoadNet(nn.Module):
    def __init__(self, pretrained: bool) -> None:
        super().__init__()
        import timm

        self.backbone = timm.create_model(BACKBONE, pretrained=pretrained, num_classes=0)
        # timm's num_features is the last stage, 960. forward() still applies the
        # pretrained 1x1 head and returns the pooled 1280-d ImageNet vector.
        width = int(self.backbone.conv_head.out_channels)
        self.trunk = nn.Sequential(
            nn.Linear(width, 256),
            nn.Hardswish(),
            nn.Dropout(0.2),
        )
        self.material = nn.Linear(256, len(MATERIAL))
        self.friction = nn.Linear(256, len(FRICTION))
        self.uneven = nn.Linear(256, len(UNEVEN))

    def forward(self, x: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        x = self.backbone(x)
        x = self.trunk(x)
        return self.material(x), self.friction(x), self.uneven(x)
