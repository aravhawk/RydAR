# RydAR research data

This folder is the copy of record for the crash tables and for the original Benton and Washington curve file. The shipped phone database is `ios/RydAR/curves.sqlite`: 168,357 curves across all 75 Arkansas counties. The public map draws 153,328 of them from `web/public/data/curves-arkansas-1.geojson` through `curves-arkansas-4.geojson`. Every feature in those four files has an empty quality flag.

The phone warns where `quality_flags` is empty, and it also skips private roads, ramps, closed loops, and corners under 50 ft. State and municipal roads stay in. The formula, the tread table, and the spoken line live in `ios/RydAR/Screening.swift`. When this folder and the app disagree, the app wins.

`tools/build_arkansas.py` is what added the other counties from the same Arkansas GIS Office layer and kept the Benton and Washington geometry in the prototype file. The shipped SQLite and the four GeoJSON parts are already built. Leave `data/curves/build_curves.py`, `tools/build_arkansas.py`, and `data/fars/compute.py` unused for a refresh. The GIS layer has no belt of roads in the surrounding states.

The long product brief lives outside this repository.

## What the prototype file contains

`curves/curves.geojson` holds 20,776 candidate segments in Benton and Washington counties, radius under 600 ft, from Arkansas GIS Office road centerlines. That 20,776 figure is the two-county extract. It is the original study file, and the shipped database is the 75-county file above.

Use the geometry, the road name, the county, the surface label, the radius, the deflection, the class, and `quality_flags`.

Leave `screening_mph_paved_wet`, `screening_mph_unpaved`, and `screening_mph_unpaved_f008` out of the warning threshold. Those three fields were computed at one superelevation, `e = +0.02`, with `f` of 0.15, 0.10, and 0.08. The app recomputes a range with `e` from −0.02 to +0.02 and speaks when speed is above the low end. Paved `f` starts at 0.15. Unpaved `f` starts at 0.10. Reported tread can only lower `f`. The 0.08 column stays in this file as a research sensitivity.

## curves/

| File | What it is |
|---|---|
| `curves.geojson` | The two-county prototype. About 23 MB. |
| `SUMMARY.md` | How that file was built, the counts, and the synthetic tests. Generated 2026-10-24 18:07 CDT. Research log for the prototype. |
| `results.json` | Machine-readable summary from the same run. |
| `build_curves.py` | The generator. `OUT` is hardcoded to `/tmp/rydar_curves`. It refetches centerlines and expects a local OSM extract. The app does not need a rerun. |

`SUMMARY.md` section 7 says 91.5% of those extracted bends lie within 20 m of a drivable OpenStreetMap way. That is a proximity check on the prototype. The app does not match curves against OpenStreetMap, and the figure is separate from a detection rate. The synthetic radius errors and the straight-road false bends in section 5 are the same kind of geometry check.

## fars/

Crash figures come from `report.txt` and the `t*.csv` tables. They were computed from NHTSA FARS 2015–2024 on Oct 24, 2026. `compute.py` downloads the national zips itself and writes to `/tmp/rydar_fars`. The raw zips are not in this folder. Quote the CSVs and `report.txt`.

The tables are the Arkansas 3rd District study: Benton, Carroll, Crawford, Madison, and Washington, with Sebastian kept separate because it is only partly in the district. They are separate from a statewide total. `crash_level_ar3_sebastian.csv` is the crash-level extract.
