#!/usr/bin/env python3
"""Build the phone curve database for every Arkansas county.

Source: Arkansas GIS Office ROADS_ACF, the same layer as the two-county file.
Roads in that layer are assigned to an Arkansas county, including centerlines
the file places on the state line. It does not contain a 25, 50, or 100 mile
belt of Missouri, Oklahoma, Texas, Louisiana, Mississippi, or Tennessee roads.
Those inventories are separate. This script does not download them and does
not mix in OpenStreetMap.

Writes /tmp/rydar_ar/curves.sqlite and /tmp/rydar_ar/curves-arkansas.geojson
(county-class roads only, for the public map). Does not replace the app file.
"""

from __future__ import annotations

import json
import sqlite3
import sys
import time
from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd
from pyproj import Transformer

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_curves as bc  # noqa: E402

OUT = Path("/tmp/rydar_ar")
OUT.mkdir(parents=True, exist_ok=True)
LAYER = bc.LAYER
CRS = bc.CRS
FT = bc.FT

FIPS = {
    "001": "Arkansas", "003": "Ashley", "005": "Baxter", "007": "Benton",
    "009": "Boone", "011": "Bradley", "013": "Calhoun", "015": "Carroll",
    "017": "Chicot", "019": "Clark", "021": "Clay", "023": "Cleburne",
    "025": "Cleveland", "027": "Columbia", "029": "Conway", "031": "Craighead",
    "033": "Crawford", "035": "Crittenden", "037": "Cross", "039": "Dallas",
    "041": "Desha", "043": "Drew", "045": "Faulkner", "047": "Franklin",
    "049": "Fulton", "051": "Garland", "053": "Grant", "055": "Greene",
    "057": "Hempstead", "059": "Hot Spring", "061": "Howard", "063": "Independence",
    "065": "Izard", "067": "Jackson", "069": "Jefferson", "071": "Johnson",
    "073": "Lafayette", "075": "Lawrence", "077": "Lee", "079": "Lincoln",
    "081": "Little River", "083": "Logan", "085": "Lonoke", "087": "Madison",
    "089": "Marion", "091": "Miller", "093": "Mississippi", "095": "Monroe",
    "097": "Montgomery", "099": "Nevada", "101": "Newton", "103": "Ouachita",
    "105": "Perry", "107": "Phillips", "109": "Pike", "111": "Poinsett",
    "113": "Polk", "115": "Pope", "117": "Prairie", "119": "Pulaski",
    "121": "Randolph", "123": "St. Francis", "125": "Saline", "127": "Scott",
    "129": "Searcy", "131": "Sebastian", "133": "Sevier", "135": "Sharp",
    "137": "Stone", "139": "Union", "141": "Van Buren", "143": "Washington",
    "145": "White", "147": "Woodruff", "149": "Yell",
}
FIPS_BY_NAME = {name: code for code, name in FIPS.items()}
FIELDS = ",".join([
    "objectid", "cn_r_fips", "cn_l_fips", "meta_id", "rd_class", "rd_design",
    "rd_surftyp", "pstr_fulnam", "state_l", "state_r",
])
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


def log(message: str) -> None:
    print(f"[{time.time() - T0:7.1f}s] {message}", flush=True)


def fetch_centerlines() -> gpd.GeoDataFrame:
    cache = OUT / "centerlines.gpkg"
    if cache.exists():
        log("using cached centerlines")
        return gpd.read_file(cache)
    query = LAYER + "/query"
    info = bc.fetch_json(LAYER, {"f": "json"})
    maxrec = info["maxRecordCount"]
    total = bc.fetch_json(query, {"where": "1=1", "returnCountOnly": "true", "f": "json"})["count"]
    log(f"server count {total} page size {maxrec}")
    offsets = list(range(0, total, maxrec))
    rows, geoms = [], []

    def page(off):
        payload = bc.fetch_json(query, {
            "where": "1=1", "outFields": FIELDS, "returnGeometry": "true", "outSR": 26915,
            "orderByFields": "objectid", "resultOffset": off, "resultRecordCount": maxrec, "f": "json",
        })
        return off, payload["features"]

    import concurrent.futures as cf
    done = 0
    with cf.ThreadPoolExecutor(8) as pool:
        for off, feats in pool.map(page, offsets):
            done += 1
            if done % 100 == 0:
                log(f"pages {done}/{len(offsets)}")
            for feature in feats:
                rows.append(feature["attributes"])
                geoms.append(bc.esri_geom(feature.get("geometry")))
    frame = gpd.GeoDataFrame(rows, geometry=geoms, crs=CRS)
    frame = frame[frame.geometry.notna()].copy()
    frame.to_file(cache, driver="GPKG")
    log(f"cached {len(frame)} centerlines")
    return frame


CARRIAGEWAY = {
    "", "sc", "dc", "dual carriage",
    "single carriageway", "dual carriageway", "frontage road",
}


def flags(row) -> str:
    found = []
    if row.closed:
        found.append("closed_loop")
    design = str(row.rd_design or "").strip().lower()
    if design not in CARRIAGEWAY:
        found.append("ramp_circle_connector")
    if row.radius_ft < 50:
        found.append("lt50ft_corner_or_hairpin")
    if row.vert_spacing_m > 25:
        found.append("sparse_vertices_gt25m")
    return ";".join(found)


def main() -> None:
    frame = fetch_centerlines()
    right = frame["cn_r_fips"].where(frame["cn_r_fips"].isin(FIPS), None)
    left = frame["cn_l_fips"].where(frame["cn_l_fips"].isin(FIPS), None)
    frame["fips"] = right.fillna(left)
    meta = frame["meta_id"].astype(str).str[-3:]
    frame["fips"] = frame["fips"].fillna(meta.where(meta.isin(FIPS)))
    neighbor = ~(frame["state_l"].fillna("AR").eq("AR") & frame["state_r"].fillna("AR").eq("AR"))
    log(f"rows {len(frame)} assigned {int(frame.fips.notna().sum())} touching a neighbor state {int(neighbor.sum())}")
    frame = frame[frame["fips"].notna()].copy()
    frame["county_name"] = frame["fips"].map(FIPS)
    frame["surface"] = frame["rd_surftyp"].fillna("Unknown")
    frame["name"] = frame["pstr_fulnam"].fillna("").str.strip()
    frame["rd_design"] = frame["rd_design"].fillna("")
    frame["rd_class"] = frame["rd_class"].fillna("")
    log("building chains")
    chains = bc.build_chains(frame, merge=True)
    log(f"chains {len(chains)}")
    found = bc.detect(chains, bc.WIN, [bc.GEO_THR], keep_geom_thr=bc.GEO_THR)
    rows = found[bc.GEO_THR]
    log(f"curves {len(rows)}")
    table = pd.DataFrame([{k: v for k, v in row.items() if k not in ("P", "pmin")} for row in rows])
    table["radius_ft"] = table["rmin_m"] / FT
    table["vert_spacing_m"] = [row.get("vert_spacing_m", 0) for row in rows]
    table["quality_flags"] = table.apply(flags, axis=1)
    transform = Transformer.from_crs(CRS, 4326, always_xy=True)
    points = np.array([row["pmin"] for row in rows])
    lon, lat = transform.transform(points[:, 0], points[:, 1])
    table["lat"] = lat
    table["lon"] = lon

    sqlite_path = OUT / "curves.sqlite"
    if sqlite_path.exists():
        sqlite_path.unlink()
    connection = sqlite3.connect(sqlite_path)
    connection.executescript(SCHEMA)
    web = []
    for index, row in enumerate(rows):
        item = table.iloc[index]
        xs, ys = transform.transform(row["P"][:, 0], row["P"][:, 1])
        coords = [[round(float(x), 5), round(float(y), 5)] for x, y in zip(xs, ys)]
        if len(coords) < 2:
            continue
        curve_id = f"{FIPS_BY_NAME[item.county]}-{int(item.chain)}-{index}"
        lons = [point[0] for point in coords]
        lats = [point[1] for point in coords]
        surface = str(item.surface).lower()
        connection.execute(
            """INSERT INTO curves VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                curve_id, item.county, item["name"] or None, surface, float(item.radius_ft),
                float(item.defl), float(item.length), item.rd_class or None, item.rd_design or None,
                item.side, 1 if item.closed else 0, item.quality_flags, None,
                float(item.lat), float(item.lon), min(lats), max(lats), min(lons), max(lons),
                json.dumps(coords, separators=(",", ":")),
            ),
        )
        if item.rd_class == "County":
            web.append({
                "type": "Feature",
                "id": index,
                "properties": {
                    "id": curve_id,
                    "county": item.county,
                    "road": item["name"] or "unnamed road",
                    "surface": "paved" if surface == "paved" else "unpaved",
                    "radius_ft": round(float(item.radius_ft)),
                    "deflection_deg": round(float(item.defl)),
                    "flags": item.quality_flags,
                },
                "geometry": {"type": "LineString", "coordinates": coords},
            })
        if index and index % 20000 == 0:
            log(f"wrote {index}")
            connection.commit()
    connection.commit()
    connection.close()
    geojson = {"type": "FeatureCollection", "features": web}
    (OUT / "curves-arkansas.geojson").write_text(json.dumps(geojson, separators=(",", ":")))
    log(f"sqlite curves {index + 1} county-class web {len(web)} sqlite bytes {sqlite_path.stat().st_size}")


if __name__ == "__main__":
    T0 = time.time()
    main()
