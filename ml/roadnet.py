"""One MobileNetV3-Small trunk, three heads. Train and convert both import this."""

from __future__ import annotations

import torch
from torch import nn
from torchvision import models

from labels import FRICTION, MATERIAL, UNEVEN


class RoadNet(nn.Module):
    def __init__(self, pretrained: bool) -> None:
        super().__init__()
        weights = models.MobileNet_V3_Small_Weights.DEFAULT if pretrained else None
        base = models.mobilenet_v3_small(weights=weights)
        self.features = base.features
        self.avgpool = base.avgpool
        width = base.classifier[0].in_features
        self.trunk = nn.Sequential(
            nn.Linear(width, 256),
            nn.Hardswish(),
            nn.Dropout(0.2),
        )
        self.material = nn.Linear(256, len(MATERIAL))
        self.friction = nn.Linear(256, len(FRICTION))
        self.uneven = nn.Linear(256, len(UNEVEN))

    def forward(self, x: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        x = self.features(x)
        x = self.avgpool(x)
        x = torch.flatten(x, 1)
        x = self.trunk(x)
        return self.material(x), self.friction(x), self.uneven(x)
