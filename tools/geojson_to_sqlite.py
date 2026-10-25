#!/usr/bin/env python3
"""Build the phone's SQLite curve file from curves.geojson.

The warning speed is not stored. The app computes it.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path


SCHEMA = """
CREATE TABLE curves (
  id TEXT PRIMARY KEY,
  county TEXT NOT NULL,
  road_name TEXT,
  surface TEXT NOT NULL,
  radius_ft REAL NOT NULL,
  deflection_deg REAL,
  length_m REAL,
  rd_class TEXT,
  rd_design TEXT,
  turn_dir TEXT,
  closed_loop INTEGER NOT NULL DEFAULT 0,
  quality_flags TEXT NOT NULL DEFAULT '',
  osm_maxspeed TEXT,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  min_lat REAL NOT NULL,
  max_lat REAL NOT NULL,
  min_lon REAL NOT NULL,
  max_lon REAL NOT NULL,
  coordinates_json TEXT NOT NULL
);
CREATE INDEX curves_bbox ON curves (min_lat, max_lat, min_lon, max_lon);
CREATE INDEX curves_county_class ON curves (county, rd_class);
"""


def features(path: Path):
    with path.open() as handle:
        for line in handle:
            text = line.strip().rstrip(",")
            if not text.startswith("{") or '"Feature"' not in text:
                continue
            yield json.loads(text)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--geojson", type=Path, default=Path("data/curves/curves.geojson"))
    parser.add_argument("--sqlite", type=Path, default=Path("ios/CurveAudit/curves.sqlite"))
    parser.add_argument("--example", type=Path, default=Path("Contracts/curve.example.json"))
    args = parser.parse_args()

    args.sqlite.parent.mkdir(parents=True, exist_ok=True)
    if args.sqlite.exists():
        args.sqlite.unlink()
    connection = sqlite3.connect(args.sqlite)
    connection.executescript(SCHEMA)
    wrote_example = False
    count = 0
    for feature in features(args.geojson):
        props = feature["properties"]
        coords = feature["geometry"]["coordinates"]
        lons = [point[0] for point in coords]
        lats = [point[1] for point in coords]
        row = (
            props["id"],
            props["county"],
            props.get("road_name"),
            props["surface"],
            props["radius_ft_est"],
            props.get("deflection_deg"),
            props.get("length_m"),
            props.get("rd_class"),
            props.get("rd_design"),
            props.get("turn_dir"),
            1 if props.get("closed_loop") else 0,
            props.get("quality_flags") or "",
            props.get("osm_maxspeed"),
            props["lat"],
            props["lon"],
            min(lats),
            max(lats),
            min(lons),
            max(lons),
            json.dumps(coords, separators=(",", ":")),
        )
        connection.execute(
            """INSERT INTO curves VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            row,
        )
        count += 1
        if not wrote_example:
            args.example.parent.mkdir(parents=True, exist_ok=True)
            args.example.write_text(json.dumps(feature, indent=2) + "\n")
            wrote_example = True
    connection.commit()
    connection.close()
    print(f"Wrote {count} curves to {args.sqlite}")


if __name__ == "__main__":
    main()
