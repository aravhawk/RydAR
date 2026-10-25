"""RSCD folder names to the three heads the phone uses.

The Mendeley class folders combine friction, material, and unevenness.
Snow and ice folders have no material and no unevenness. Gravel and mud
folders have no unevenness. A missing head is masked in the loss. It is
not the can't-tell class. Can't-tell is only for non-road images.
"""

from __future__ import annotations

MATERIAL = ("paved", "unpaved", "cant_tell")
FRICTION = ("dry", "wet", "water", "snow_ice", "cant_tell")
UNEVEN = ("smooth", "slight", "severe", "cant_tell")

MASK = -1


def _norm(folder_name: str) -> str:
    return folder_name.lower().replace("_", "-").replace(" ", "-")


def parse_folder(folder_name: str) -> tuple[int, int, int] | None:
    name = _norm(folder_name)
    if any(word in name for word in ("snow", "ice")):
        return (MASK, FRICTION.index("snow_ice"), MASK)

    if "asphalt" in name or "concrete" in name:
        material = MATERIAL.index("paved")
    elif "gravel" in name or "mud" in name or "dirt" in name:
        material = MATERIAL.index("unpaved")
    else:
        return None

    if "water" in name:
        friction = FRICTION.index("water")
    elif "wet" in name:
        friction = FRICTION.index("wet")
    elif "dry" in name:
        friction = FRICTION.index("dry")
    else:
        return None

    if "severe" in name:
        uneven = UNEVEN.index("severe")
    elif "slight" in name:
        uneven = UNEVEN.index("slight")
    elif "smooth" in name:
        uneven = UNEVEN.index("smooth")
    else:
        uneven = MASK
    return (material, friction, uneven)


def cant_tell_target() -> tuple[int, int, int]:
    return (
        MATERIAL.index("cant_tell"),
        FRICTION.index("cant_tell"),
        UNEVEN.index("cant_tell"),
    )
