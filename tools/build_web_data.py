#!/usr/bin/env python3
"""Build the public map's county files from curves.geojson.

County-class roads only. Geometry and descriptive fields only: no screening
speeds, no scores, no ordering by anything but curve id. The public page says
"candidates for engineering review", so nothing here ranks a curve.

    python3 tools/build_web_data.py

Writes web/public/data/curves-benton.geojson and curves-washington.geojson.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

COUNTIES = {
    "Benton": ("007-", "curves-benton.geojson"),
    "Washington": ("143-", "curves-washington.geojson"),
}


def features(path: Path):
    with path.open() as handle:
        for line in handle:
            text = line.strip().rstrip(",")
            if not text.startswith("{") or '"Feature"' not in text:
                continue
            yield json.loads(text)


def id_key(curve_id: str) -> tuple[int, int, int]:
    county, chain, index = curve_id.split("-")
    return int(county), int(chain), int(index)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--geojson", type=Path, default=Path("data/curves/curves.geojson"))
    parser.add_argument("--out", type=Path, default=Path("web/public/data"))
    args = parser.parse_args()

    out: dict[str, list[dict]] = {name: [] for name in COUNTIES}
    for feature in features(args.geojson):
        props = feature["properties"]
        if props.get("rd_class") != "County":
            continue
        county = props["county"]
        prefix = COUNTIES[county][0]
        if not props["id"].startswith(prefix):
            raise SystemExit(f"{props['id']} does not start with {prefix} ({county})")
        out[county].append(
            {
                "type": "Feature",
                "properties": {
                    "id": props["id"],
                    "county": county,
                    "road": props.get("road_name") or "unnamed road",
                    "surface": props["surface"],
                    "radius_ft": round(props["radius_ft_est"]),
                    "deflection_deg": round(props["deflection_deg"]),
                    "flags": props.get("quality_flags") or "",
                },
                "geometry": {
                    "type": "LineString",
                    "coordinates": [
                        [round(x, 5), round(y, 5)] for x, y in feature["geometry"]["coordinates"]
                    ],
                },
            }
        )

    args.out.mkdir(parents=True, exist_ok=True)
    for county, (_, name) in COUNTIES.items():
        rows = sorted(out[county], key=lambda f: id_key(f["properties"]["id"]))
        clean = sum(1 for f in rows if not f["properties"]["flags"])
        path = args.out / name
        path.write_text(
            json.dumps({"type": "FeatureCollection", "features": rows}, separators=(",", ":")) + "\n"
        )
        print(f"{county}: {len(rows)} county-class curves ({clean} without quality flags) -> {path}")


if __name__ == "__main__":
    main()
