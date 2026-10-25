# CurveAudit AR — research data (frozen Oct 24, 2026)

The product spec in this repo is `docs/CurveAudit-AR-Product-Brief.md`. If this folder and that file disagree, the **build contract** at the top of the brief wins. This folder is the copy of record. The Downloads copy of these files has been removed.

This folder is the evidence and the prototype curve file. It is not the app.

## What to ship in the app

`curves/curves.geojson` — 20,776 candidate curve segments in Benton and Washington counties, radius under 600 ft, from Arkansas GIS Office road centerlines.

Use the geometry, the road name, the county, the surface label, the radius, the deflection, the class, and `quality_flags`.

Do **not** use `screening_mph_paved_wet`, `screening_mph_unpaved`, or `screening_mph_unpaved_f008` as the warning threshold. Those three fields were computed at one superelevation, `e = +0.02`, with `f` of 0.15, 0.10, and 0.08. The app recomputes a range with `e` from −0.02 to +0.02 and speaks when speed is above the low end. Paved `f = 0.15`. Unpaved `f = 0.10`. The 0.08 column stays in this file as a research sensitivity only.

Warn only where `quality_flags` is empty. Skip private roads, ramps, closed loops, and corners flagged under 50 ft. The public county map and county PDF are county-class roads only. Driving warnings may also include state and municipal roads.

## curves/

| File | What it is |
|---|---|
| `curves.geojson` | The prototype database. 23 MB. |
| `SUMMARY.md` | How the file was built, counts, and the synthetic tests. Generated 2026-10-24 18:07 CDT. Research log, not the app spec. |
| `results.json` | Machine-readable summary from the same run. |
| `build_curves.py` | The generator. `OUT` is hardcoded to `/tmp/curveaudit_curves`. It refetches centerlines and expects a local OSM extract. You do not need to rerun it to build the app. |

## fars/

Crash figures in the brief come from `report.txt` and the `t*.csv` tables. They were computed from NHTSA FARS 2015–2024 on Oct 24, 2026. `compute.py` downloads the national zips itself and writes to `/tmp/curveaudit_fars`. The raw zips are not in this folder. Quote the CSVs and `report.txt`, not a fresh memory of the percentages.

`crash_level_ar3_sebastian.csv` is the crash-level extract. Sebastian County is only partly in AR-3 and is kept separate from the five-county totals.
