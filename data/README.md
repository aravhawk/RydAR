# RydAR — research data

The two-county curve study below is the original Benton and Washington file. `tools/build_arkansas.py` adds the other Arkansas counties from the same Arkansas GIS Office layer and keeps these Benton and Washington curves unchanged. That layer does not include a belt of roads in the surrounding states.

This folder is the copy of record for the crash tables and the original two-county curve file. The product brief is not in the repository. If this folder and the app disagree, the app wins: the formula, the tread table, and the spoken line live in `ios/RydAR/Screening.swift`.

This folder is the evidence and the prototype curve file. It is not the app.

## What to ship in the app

`curves/curves.geojson` — 20,776 candidate curve segments in Benton and Washington counties, radius under 600 ft, from Arkansas GIS Office road centerlines.

Use the geometry, the road name, the county, the surface label, the radius, the deflection, the class, and `quality_flags`.

Do **not** use `screening_mph_paved_wet`, `screening_mph_unpaved`, or `screening_mph_unpaved_f008` as the warning threshold. Those three fields were computed at one superelevation, `e = +0.02`, with `f` of 0.15, 0.10, and 0.08. The app recomputes a range with `e` from −0.02 to +0.02 and speaks when speed is above the low end. Paved `f = 0.15`. Unpaved `f = 0.10`. The 0.08 column stays in this file as a research sensitivity only.

Warn only where `quality_flags` is empty. Skip private roads, ramps, closed loops, and corners flagged under 50 ft. The shipped phone database and the public map are the warnable bends in all 75 counties, including state and municipal roads. Loops, ramps, and corners under 50 ft stay off both. The 20,776 figure below is the original Benton and Washington extract, not the shipped count.

## curves/

| File | What it is |
|---|---|
| `curves.geojson` | The prototype database. 23 MB. |
| `SUMMARY.md` | How the file was built, counts, and the synthetic tests. Generated 2026-10-24 18:07 CDT. Research log, not the app spec. |
| `results.json` | Machine-readable summary from the same run. |
| `build_curves.py` | The generator. `OUT` is hardcoded to `/tmp/rydar_curves`. It refetches centerlines and expects a local OSM extract. You do not need to rerun it to build the app. |

## fars/

Crash figures in the brief come from `report.txt` and the `t*.csv` tables. They were computed from NHTSA FARS 2015–2024 on Oct 24, 2026. `compute.py` downloads the national zips itself and writes to `/tmp/rydar_fars`. The raw zips are not in this folder. Quote the CSVs and `report.txt`, not a fresh memory of the percentages.

`crash_level_ar3_sebastian.csv` is the crash-level extract. Sebastian County is only partly in AR-3 and is kept separate from the five-county totals.
