# RydAR curve-screening prototype — Benton + Washington Counties, AR

Generated 2026-10-24 18:07:13 CDT by `/tmp/rydar_curves/build_curves.py`. **All speeds below are screening assumptions (AASHTO simple-curve formula), NOT legal advisory speeds.**

## 1. Data pulled

* Centerlines: `https://gis.arkansas.gov/arcgis/rest/services/FEATURESERVICES/Transportation/MapServer/18` (ROADS_ACF, ArcGIS Server 11.5), native SR EPSG:26915.
* Query `where`: `cn_r_fips IN ('007','143') OR cn_l_fips IN ('007','143')` — FIPS fields are **3-digit** (`007`,`143`), not `05007`/`05143`; `ah_county` is null on every row I sampled (0 rows match 'Benton%'/'Washington%').
* **maxRecordCount = 200** per request (pagination via `resultOffset` + `orderByFields=objectid` works; `supportedQueryFormats` JSON/geoJSON/PBF). Server count for union where = 48,303; 242 pages fetched (page size min/max [103, 200]); rows fetched 48,303; unique objectid 48,303; null geometry 0; fetch retries/failures logged: 0.
* Count by FIPS field: Benton: cn_r_fips=29,346, cn_l_fips=29,290; Washington: cn_r_fips=18,910, cn_l_fips=18,996.
* County assignment used: cn_r_fips, else cn_l_fips, else `meta_id`. Records kept: 48,303 (unassignable: 0). Rows with different left/right county FIPS (boundary roads): 133. Rows where my county != `meta_id` county: 49. Some kept rows are in OK/MO (state_l/state_r) next to the border.
* Full field list (name, type, length):

```
objectid           OID  
unique_id          Integer  
pl_add_f           Integer  
pl_add_t           Integer  
pr_add_f           Integer  
pr_add_t           Integer  
pre_dir            String  2
pre_type           String  4
pstr_nam           String  72
pstr_type          String  4
psuf_dir           String  2
pstr_fulnam        String  255
city_l             String  30
city_r             String  30
comm_l             String  30
comm_r             String  30
zip5_l             String  5
zip5_r             String  5
cn_r_fips          String  3
cn_l_fips          String  3
state_l            String  2
state_r            String  2
meta_id            String  20
a1_lfadd           String  10
a1_ltadd           String  10
a1_rfadd           String  10
a1_rtadd           String  10
a1_drpr            String  2
a1_prtyp           String  255
a1_str             String  72
a1_styp            String  4
a1_drsf            String  2
a1_fulnam          String  255
a2_lfadd           String  10
a2_ltadd           String  10
a2_rfadd           String  10
a2_rtadd           String  10
a2_drpr            String  2
a2_prtyp           String  255
a2_str             String  72
a2_styp            String  4
a2_drsf            String  2
a2_fulnam          String  255
a3_lfadd           String  10
a3_ltadd           String  10
a3_rfadd           String  10
a3_rtadd           String  10
a3_drpr            String  2
a3_prtyp           String  255
a3_str             String  72
a3_styp            String  4
a3_drsf            String  2
a3_fulnam          String  255
rd_class           String  25
rd_design          String  25
rd_surftyp         String  25
log_direct         String  25
ah_dist            String  2
ah_county          String  25
ah_route           String  100
ah_section         String  3
ah_blm             Double  
ah_elm             Double  
ah_length          Double  
ah_seg_num         Double  
ah_rev_acf         String  3
ah_id              String  150
ah_roadid          String  150
ah_signed          String  10
date_ed            String  8
aggregate_id       String  50
shape              Geometry  
globalid           GlobalID  38
st_length(shape)   Double  
```
Notes: there is **no `rd_name` field**; road name is `pstr_fulnam` (also `a1/a2/a3_fulnam` alternates). No speed-limit field of any kind exists in the layer. Extra fields: `rd_design` (Single/Dual Carriageway, ramps…), `ah_*` (ARDOT linear-ref, blank for these counties), `date_ed`.

* `date_ed` (only edit-date field; string YYYYMMDD) range: **20260107 – 20260701**; distinct values and row counts: {'20260107': 7365, '20260109': 4439, '20260115': 7141, '20260701': 29358}. These look like batch stamps from county-level loads rather than per-feature edit times.

| county_name | min | max |
|---|---|---|
| Benton | 20260115 | 20260701 |
| Washington | 20260107 | 20260701 |

## 2. Records and miles (centerlines)

Counts by `rd_class` × `rd_surftyp` per county:

| county_name | rd_class | Paved | Unpaved |
|---|---|---|---|
| Benton | County | 2,212 | 1,947 |
| Benton | Federal | 789 | 0 |
| Benton | Municipal | 20,421 | 1,336 |
| Benton | Private | 276 | 357 |
| Benton | State | 1,999 | 48 |
| Washington | County | 1,513 | 911 |
| Washington | Federal | 18 | 8 |
| Washington | Municipal | 11,970 | 162 |
| Washington | Private | 1,529 | 709 |
| Washington | State | 2,024 | 74 |

Miles (computed in UTM 15N; ratio to server `st_length(shape)` = 1.00000):

| county_name | rd_class | Paved | Unpaved |
|---|---|---|---|
| Benton | County | 487.5 | 710.9 |
| Benton | Federal | 186.3 | 0.0 |
| Benton | Municipal | 1,916.2 | 168.7 |
| Benton | Private | 42.9 | 76.1 |
| Benton | State | 328.8 | 27.5 |
| Washington | County | 472.1 | 535.1 |
| Washington | Federal | 10.5 | 7.7 |
| Washington | Municipal | 1,095.4 | 32.7 |
| Washington | Private | 116.0 | 219.3 |
| Washington | State | 410.6 | 9.2 |

Miles by surface, all classes:

| county_name | Paved | Unpaved |
|---|---|---|
| Benton | 2,961.8 | 983.3 |
| Washington | 2,104.6 | 803.9 |

County-class (`rd_class='County'`) subset — segment counts and miles:

| county_name | Paved | Unpaved |
|---|---|---|
| Benton | 2,212 | 1,947 |
| Washington | 1,513 | 911 |

| county_name | Paved | Unpaved |
|---|---|---|
| Benton | 487.5 | 710.9 |
| Washington | 472.1 | 535.1 |

`rd_design` counts: {'Single Carriageway': 45053, 'Dual Carriageway': 2181, 'At-Grade Ramp': 477, 'Traffic Circle': 282, 'Connector Segment': 107, 'Grade-Separated Ramp': 66, 'Frontage Road': 66, 'Grade Separated Ramp': 64, 'At Grade Ramp': 5, 'Grade-Seperated Ramp': 2}

## 3. Digitization vertex spacing (original ACF vertices)

* 348,559 vertex gaps; **median 19.0 m**, p10 5.6 m, p90 68.2 m; share of gaps >20 m: 47.6%; >50 m: 15.6%; mean vertices per segment 8.2.
* Median local vertex spacing in windows around the detected <600 ft curves: 21.2 m.

| cls | surface | median | p90 | n |
|---|---|---|---|---|
| County | Paved | 19.7 | 54.7 | 53,572 |
| County | Unpaved | 18.8 | 53.6 | 71,030 |
| Federal | Paved | 39.2 | 95.2 | 6,180 |
| Federal | Unpaved | 18.3 | 41.3 | 536 |
| Municipal | Paved | 18.2 | 84.3 | 142,210 |
| Municipal | Unpaved | 18.9 | 68.0 | 10,078 |
| Private | Paved | 10.2 | 51.0 | 12,118 |
| Private | Unpaved | 15.5 | 46.9 | 20,280 |
| State | Paved | 25.6 | 77.8 | 30,816 |
| State | Unpaved | 21.9 | 75.3 | 1,739 |

Curve density vs chain median vertex spacing (R<600 ft, ≥30 m):

| bin | chains | km | curves_lt600ft | curves_per_100km |
|---|---|---|---|---|
| <=10 m | 3,087 | 754.8 | 2,471 | 327.4 |
| 10-25 m | 7,835 | 4,652.9 | 14,190 | 305.0 |
| 25-50 m | 4,964 | 3,333.9 | 3,738 | 112.1 |
| >50 m | 5,576 | 2,288.2 | 377 | 16.5 |

Sensitivity of counts to method choices:

| run | <150ft | <150ft county-class | <300ft | <300ft county-class | <600ft | <600ft county-class |
|---|---|---|---|---|---|---|
| main: win 40 m, merged chains | 2,296 | 657 | 10,174 | 3,596 | 20,776 | 8,037 |
| window 30 m | 1,912 | 571 | 9,160 | 3,291 | 19,350 | 7,565 |
| window 60 m | 3,032 | 824 | 10,551 | 3,753 | 21,098 | 8,258 |
| no chain merge (each segment alone) | 1,742 | 547 | 8,622 | 3,166 | 18,235 | 7,379 |
| vertices decimated 2x (every other vertex) | 2,039 | 625 | 8,224 | 3,023 | 16,079 | 6,112 |

## 4. Curves detected

Method: UTM 15N (EPSG:26915) → merge same-name/class/surface/design segments at 2-way nodes (21,462 chains from 48,303 segments) → resample every 5 m → signed Menger curvature of (i−k, i, i+k) with outer points 40 m apart along the arc (±20 m) → 3-sample moving average of curvature (15 m) → contiguous same-direction stretch with R<threshold for ≥30 m. Radius reported = minimum smoothed radius in the stretch; deflection = summed heading change over the stretch. No estimate within 20 m of a chain end (open chains). Main run time: 7 s.

Number of curves (per threshold; 800/1700 ft are supplementary for the speed buckets only):

| R threshold | curves |
|---|---|
| <150 ft | 2,296 |
| <300 ft | 10,174 |
| <600 ft | 20,776 |
| <800 ft | 24,855 |
| <1700 ft | 33,349 |

By county × class group × surface:

| county | class_grp | surface | R<600 ft | R<300 ft | R<150 ft |
|---|---|---|---|---|---|
| Benton | County | Paved | 1,851 | 845 | 165 |
| Benton | County | Unpaved | 2,686 | 1,287 | 245 |
| Benton | Other | Paved | 7,085 | 3,633 | 912 |
| Benton | Other | Unpaved | 960 | 525 | 124 |
| Washington | County | Paved | 1,357 | 549 | 83 |
| Washington | County | Unpaved | 2,143 | 915 | 164 |
| Washington | Other | Paved | 3,376 | 1,773 | 466 |
| Washington | Other | Unpaved | 1,318 | 647 | 137 |

By county × rd_class × surface (R<600 ft):

| county | rd_class | Paved | Unpaved |
|---|---|---|---|
| Benton | County | 1,851 | 2,686 |
| Benton | Federal | 138 | 0 |
| Benton | Municipal | 6,248 | 494 |
| Benton | Private | 250 | 345 |
| Benton | State | 449 | 121 |
| Washington | County | 1,357 | 2,143 |
| Washington | Federal | 22 | 35 |
| Washington | Municipal | 2,495 | 113 |
| Washington | Private | 503 | 1,150 |
| Washington | State | 356 | 20 |

R<600 ft curves by `rd_design`: {'Single Carriageway': 20082, 'Dual Carriageway': 478, 'At-Grade Ramp': 107, 'Traffic Circle': 43, 'Grade Separated Ramp': 28, 'Frontage Road': 24, 'Grade-Separated Ramp': 5, 'At Grade Ramp': 5, 'Connector Segment': 3, 'Grade-Seperated Ramp': 1}; closed loops (cul-de-sacs/roundabouts): 959.

Radius distribution of detected curves (ft; radius_ft_est = min smoothed radius in stretch):

| threshold_ft | subset | n | median_ft | p10_ft | min_ft | median_len_m | median_defl_deg |
|---|---|---|---|---|---|---|---|
| 600 | all curves | 20,776 | 158.7 | 63.0 | 17.6 | 49.7 | 50.6 |
| 600 | County-class roads | 8,037 | 180.2 | 76.7 | 18.8 | 50.0 | 46.2 |
| 600 | unpaved (all classes) | 7,107 | 160.3 | 70.8 | 31.7 | 45.2 | 49.2 |
| 600 | County-class unpaved | 4,829 | 170.5 | 74.5 | 31.7 | 49.9 | 46.9 |
| 600 | County-class paved | 3,208 | 192.2 | 81.0 | 18.8 | 50.0 | 45.4 |
| 300 | all curves | 10,174 | 103.4 | 55.8 | 17.6 | 40.0 | 74.8 |
| 300 | County-class roads | 3,596 | 114.6 | 63.8 | 18.8 | 40.0 | 67.7 |
| 300 | unpaved (all classes) | 3,374 | 105.6 | 61.8 | 31.7 | 40.0 | 70.6 |
| 300 | County-class unpaved | 2,202 | 110.1 | 63.9 | 31.7 | 40.0 | 69.2 |
| 300 | County-class paved | 1,394 | 123.5 | 63.8 | 18.8 | 40.5 | 65.1 |
| 150 | all curves | 2,296 | 71.7 | 34.6 | 17.6 | 35.0 | 91.5 |
| 150 | County-class roads | 657 | 76.1 | 53.7 | 18.8 | 35.0 | 87.2 |
| 150 | unpaved (all classes) | 670 | 73.7 | 48.5 | 32.3 | 35.0 | 89.6 |
| 150 | County-class unpaved | 409 | 75.3 | 53.4 | 32.3 | 35.0 | 86.7 |
| 150 | County-class paved | 248 | 76.4 | 55.9 | 18.8 | 35.0 | 88.7 |

Quality flags on the 20,776 R<600 ft curves (heuristic; a curve can have several): {'(none)': 12187, 'sparse_vertices_gt25m': 7752, 'closed_loop': 959, 'lt50ft_corner_or_hairpin': 857, 'ramp_circle_connector': 192}. Curves with no flag ('clean'): 12,187.

| county | class_grp | surface | clean R<600ft | clean R<300ft (min radius) |
|---|---|---|---|---|
| Benton | County | Paved | 1,148 | 1,047 |
| Benton | County | Unpaved | 1,689 | 1,510 |
| Benton | Other | Paved | 2,826 | 2,495 |
| Benton | Other | Unpaved | 390 | 366 |
| Washington | County | Paved | 1,059 | 844 |
| Washington | County | Unpaved | 1,600 | 1,454 |
| Washington | Other | Paved | 2,418 | 2,084 |
| Washington | Other | Unpaved | 1,057 | 990 |

Curve density per 100 road-miles:

| threshold_ft | county | county_class | surface | curves | road_miles | curves_per_100mi |
|---|---|---|---|---|---|---|
| 600 | Benton | Other | Paved | 7,085 | 2,474.28 | 286.35 |
| 600 | Benton | Other | Unpaved | 960 | 272.35 | 352.49 |
| 600 | Benton | County | Paved | 1,851 | 487.48 | 379.71 |
| 600 | Benton | County | Unpaved | 2,686 | 710.95 | 377.81 |
| 600 | Washington | Other | Paved | 3,376 | 1,632.51 | 206.80 |
| 600 | Washington | Other | Unpaved | 1,318 | 268.80 | 490.33 |
| 600 | Washington | County | Paved | 1,357 | 472.12 | 287.43 |
| 600 | Washington | County | Unpaved | 2,143 | 535.12 | 400.47 |
| 300 | Benton | Other | Paved | 3,633 | 2,474.28 | 146.83 |
| 300 | Benton | Other | Unpaved | 525 | 272.35 | 192.77 |
| 300 | Benton | County | Paved | 845 | 487.48 | 173.34 |
| 300 | Benton | County | Unpaved | 1,287 | 710.95 | 181.03 |
| 300 | Washington | Other | Paved | 1,773 | 1,632.51 | 108.61 |
| 300 | Washington | Other | Unpaved | 647 | 268.80 | 240.70 |
| 300 | Washington | County | Paved | 549 | 472.12 | 116.29 |
| 300 | Washington | County | Unpaved | 915 | 535.12 | 170.99 |
| 150 | Benton | Other | Paved | 912 | 2,474.28 | 36.86 |
| 150 | Benton | Other | Unpaved | 124 | 272.35 | 45.53 |
| 150 | Benton | County | Paved | 165 | 487.48 | 33.85 |
| 150 | Benton | County | Unpaved | 245 | 710.95 | 34.46 |
| 150 | Washington | Other | Paved | 466 | 1,632.51 | 28.55 |
| 150 | Washington | Other | Unpaved | 137 | 268.80 | 50.97 |
| 150 | Washington | County | Paved | 83 | 472.12 | 17.58 |
| 150 | Washington | County | Unpaved | 164 | 535.12 | 30.65 |

## 5. Method validation

(a) Synthetic 90° circular arc with 80 m tangents each side, vertices every 10 m or 25 m, Gaussian noise (σ per axis) on every vertex, 200 trials/cell. `arc` = median radius over the arc interior; `pipeline` = what the app would report (min radius in a <600 ft stretch overlapping the arc).

| R_true_ft | vertex_spacing_m | noise_sigma_m | median_arc_R_est_over_true | p10_p90_arc_ratio | median_abs_err_pct | detect_rate_lt600ft | pipeline_rmin_over_true_median | pipeline_p10_p90 |
|---|---|---|---|---|---|---|---|---|
| 100 | 10.00 | 0.00 | 1.02 | 1.02-1.02 | 1.80 | 1.00 | 1.00 | 1.00-1.00 |
| 100 | 10.00 | 1.00 | 1.04 | 0.94-1.16 | 5.59 | 1.00 | 0.96 | 0.85-1.06 |
| 100 | 10.00 | 3.00 | 1.14 | 0.83-2.52 | 20.11 | 0.88 | 0.74 | 0.60-0.95 |
| 100 | 25.00 | 0.00 | 1.10 | 1.10-1.10 | 9.53 | 1.00 | 0.95 | 0.95-0.95 |
| 100 | 25.00 | 1.00 | 1.07 | 0.92-1.18 | 8.84 | 1.00 | 0.93 | 0.81-1.04 |
| 100 | 25.00 | 3.00 | 1.06 | 0.79-1.58 | 17.89 | 0.99 | 0.86 | 0.64-1.14 |
| 200 | 10.00 | 0.00 | 1.00 | 1.00-1.00 | 0.15 | 1.00 | 1.00 | 1.00-1.00 |
| 200 | 10.00 | 1.00 | 1.02 | 0.95-1.12 | 4.16 | 1.00 | 0.74 | 0.65-0.84 |
| 200 | 10.00 | 3.00 | 1.00 | 0.80-1.49 | 14.45 | 0.81 | 0.51 | 0.40-0.65 |
| 200 | 25.00 | 0.00 | 1.00 | 1.00-1.00 | 0.47 | 1.00 | 0.94 | 0.94-0.94 |
| 200 | 25.00 | 1.00 | 1.03 | 0.97-1.14 | 4.85 | 1.00 | 0.78 | 0.69-0.88 |
| 200 | 25.00 | 3.00 | 1.03 | 0.86-1.43 | 11.31 | 0.98 | 0.60 | 0.46-0.73 |
| 500 | 10.00 | 0.00 | 1.00 | 1.00-1.00 | 0.02 | 1.00 | 1.00 | 1.00-1.00 |
| 500 | 10.00 | 1.00 | 1.01 | 0.92-1.11 | 5.10 | 0.69 | 0.59 | 0.50-0.71 |
| 500 | 10.00 | 3.00 | 0.58 | 0.42-0.75 | 41.70 | 0.55 | 0.30 | 0.20-0.43 |
| 500 | 25.00 | 0.00 | 0.98 | 0.98-0.98 | 2.28 | 1.00 | 0.96 | 0.96-0.96 |
| 500 | 25.00 | 1.00 | 1.02 | 0.94-1.12 | 4.82 | 0.94 | 0.60 | 0.49-0.71 |
| 500 | 25.00 | 3.00 | 0.88 | 0.66-1.21 | 16.63 | 0.88 | 0.36 | 0.25-0.54 |

False positives on a perfectly straight road with the same vertex noise:

| vertex_spacing_m | noise_sigma_m | straight_km_tested | false_curves_lt600ft_per_km | false_curves_lt300ft_per_km |
|---|---|---|---|---|
| 10.000 | 0.000 | 2.000 | 0.000 | 0.000 |
| 10.000 | 1.000 | 100.000 | 0.000 | 0.000 |
| 10.000 | 3.000 | 100.000 | 0.800 | 0.060 |
| 25.000 | 0.000 | 2.000 | 0.000 | 0.000 |
| 25.000 | 1.000 | 100.000 | 0.000 | 0.000 |
| 25.000 | 3.000 | 100.000 | 1.160 | 0.020 |

(b) Real examples (sharp, County-class, single carriageway, deflection ≥45°, 100–300 ft, vertex spacing ≤15 m). Last radius column re-runs the identical algorithm on the nearest OSM way as an independent geometry check. These are NOT verified against imagery by this script.

| county | surface | road | lat | lon | radius_ft_acf | deflection_deg | length_m | vertex_spacing_m | osm_way_radius_ft_same_algorithm | candidates_tried | osm_link |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Benton | Paved | Brightwater Xing | 36.369652 | -94.034242 | 101.0 | 135.0 | 100.0 | 12.7 | 103.0 | 3 | https://www.openstreetmap.org/?mlat=36.369652&mlon=-94.034242#map=19/36.369652/-94.034242 |
| Washington | Unpaved | Grove Dr | 36.223624 | -94.019884 | 100.0 | 68.0 | 55.0 | 13.6 | 101.0 | 1 | https://www.openstreetmap.org/?mlat=36.223624&mlon=-94.019884#map=19/36.223624/-94.019884 |
| Benton | Unpaved | Canyon Village Rd | 36.320428 | -93.984527 | 101.0 | 66.0 | 50.0 | 12.9 | 119.0 | 2 | https://www.openstreetmap.org/?mlat=36.320428&mlon=-93.984527#map=19/36.320428/-93.984527 |

Satellite links:
* Brightwater Xing (Benton, Paved): https://www.google.com/maps/@36.369652,-94.034242,19z/data=!3m1!1e3
* Grove Dr (Washington, Unpaved): https://www.google.com/maps/@36.223624,-94.019884,19z/data=!3m1!1e3
* Canyon Village Rd (Benton, Unpaved): https://www.google.com/maps/@36.320428,-93.984527,19z/data=!3m1!1e3

## 6. Screening speeds

V = sqrt(15·R·(e+f)), R in ft, V in mph, e = 0.02 assumed, f = 0.15 (paved wet design assumption), 0.10 and 0.08 (unpaved assumptions). **Screening assumption only — not a legal or engineering advisory speed.**

Radius at which each speed is reached:

| assumption | R_ft_for_25mph | R_ft_for_35mph | R_ft_for_45mph |
|---|---|---|---|
| paved wet f=0.15 | 245 | 480 | 794 |
| unpaved f=0.10 | 347 | 681 | 1,125 |
| unpaved f=0.08 | 417 | 817 | 1,350 |

Curves below each speed (R_thr = detection cutoff; paved rows use f=0.15, unpaved rows f=0.10 and f=0.08; bucket counts are capped by the detection cutoff — paved '<45 mph' needs R<794 ft (only the 800-ft run is complete); unpaved '<45 mph' needs R<1,125 ft (f=0.10) / 1,350 ft (f=0.08) so only the 1,700-ft run is complete, and long-radius detections are the most noise-sensitive):

| R_thr_ft | surface | assumption | subset | n_curves | <25mph | <35mph | <45mph | median_mph |
|---|---|---|---|---|---|---|---|---|
| 150 | Paved | paved wet f=0.15 | all classes | 1,626 | 1,626 | 1,626 | 1,626 | 13.4 |
| 150 | Paved | paved wet f=0.15 | County-class | 248 | 248 | 248 | 248 | 14.0 |
| 150 | Unpaved | unpaved f=0.10 | all classes | 670 | 670 | 670 | 670 | 11.5 |
| 150 | Unpaved | unpaved f=0.10 | County-class | 409 | 409 | 409 | 409 | 11.6 |
| 150 | Unpaved | unpaved f=0.08 | all classes | 670 | 670 | 670 | 670 | 10.5 |
| 150 | Unpaved | unpaved f=0.08 | County-class | 409 | 409 | 409 | 409 | 10.6 |
| 300 | Paved | paved wet f=0.15 | all classes | 6,800 | 6,707 | 6,800 | 6,800 | 16.1 |
| 300 | Paved | paved wet f=0.15 | County-class | 1,394 | 1,372 | 1,394 | 1,394 | 17.7 |
| 300 | Unpaved | unpaved f=0.10 | all classes | 3,374 | 3,374 | 3,374 | 3,374 | 13.8 |
| 300 | Unpaved | unpaved f=0.10 | County-class | 2,202 | 2,202 | 2,202 | 2,202 | 14.1 |
| 300 | Unpaved | unpaved f=0.08 | all classes | 3,374 | 3,374 | 3,374 | 3,374 | 12.6 |
| 300 | Unpaved | unpaved f=0.08 | County-class | 2,202 | 2,202 | 2,202 | 2,202 | 12.9 |
| 600 | Paved | paved wet f=0.15 | all classes | 13,669 | 10,283 | 13,578 | 13,669 | 20.0 |
| 600 | Paved | paved wet f=0.15 | County-class | 3,208 | 2,125 | 3,192 | 3,208 | 22.1 |
| 600 | Unpaved | unpaved f=0.10 | all classes | 7,107 | 6,648 | 7,107 | 7,107 | 17.0 |
| 600 | Unpaved | unpaved f=0.10 | County-class | 4,829 | 4,467 | 4,829 | 4,829 | 17.5 |
| 600 | Unpaved | unpaved f=0.08 | all classes | 7,107 | 6,988 | 7,107 | 7,107 | 15.5 |
| 600 | Unpaved | unpaved f=0.08 | County-class | 4,829 | 4,734 | 4,829 | 4,829 | 16.0 |
| 800 | Paved | paved wet f=0.15 | all classes | 16,277 | 10,917 | 15,566 | 16,277 | 21.4 |
| 800 | Paved | paved wet f=0.15 | County-class | 3,923 | 2,217 | 3,715 | 3,923 | 23.7 |
| 800 | Unpaved | unpaved f=0.10 | all classes | 8,578 | 7,443 | 8,576 | 8,578 | 18.1 |
| 800 | Unpaved | unpaved f=0.10 | County-class | 5,865 | 4,981 | 5,863 | 5,865 | 18.7 |
| 800 | Unpaved | unpaved f=0.08 | all classes | 8,578 | 8,018 | 8,578 | 8,578 | 16.5 |
| 800 | Unpaved | unpaved f=0.08 | County-class | 5,865 | 5,425 | 5,865 | 5,865 | 17.1 |
| 1,700 | Paved | paved wet f=0.15 | all classes | 21,747 | 11,712 | 18,245 | 20,944 | 24.0 |
| 1,700 | Paved | paved wet f=0.15 | County-class | 5,392 | 2,294 | 4,203 | 5,139 | 26.7 |
| 1,700 | Unpaved | unpaved f=0.10 | all classes | 11,602 | 8,385 | 11,022 | 11,567 | 20.2 |
| 1,700 | Unpaved | unpaved f=0.10 | County-class | 7,938 | 5,526 | 7,505 | 7,911 | 20.9 |
| 1,700 | Unpaved | unpaved f=0.08 | all classes | 11,602 | 9,359 | 11,350 | 11,598 | 18.5 |
| 1,700 | Unpaved | unpaved f=0.08 | County-class | 7,938 | 6,250 | 7,757 | 7,935 | 19.1 |

## 7. OpenStreetMap (Geofabrik arkansas-latest.osm.pbf, md5 c28afa97… verified against .md5)

* Read via pyogrio/GDAL OSM driver, layer `lines`, `highway IS NOT NULL`, bbox of the two counties: 92,549 ways; after clipping to TIGERweb county polygons: 93,695 line pieces. Drivable road classes (motorway…unclassified, residential, living_street, track + links; excludes service/footway/path): 27,878 pieces, 11,019 km.
* `ah_*` fields non-null counts (all 12 columns): {'ah_dist': 0, 'ah_county': 0, 'ah_route': 0, 'ah_section': 0, 'ah_blm': 0, 'ah_elm': 0, 'ah_length': 0, 'ah_seg_num': 0, 'ah_rev_acf': 0, 'ah_id': 0, 'ah_roadid': 0, 'ah_signed': 0}.
* `maxspeed` values on OSM ways matched to ACF County-class roads: {'30 mph': 875, '35 mph': 686, '45 mph': 493, '50 mph': 467, '40 mph': 348, '25 mph': 317, '55 mph': 258, '20 mph': 52, '75 mph': 5, '70 mph': 2}.
* Tag totals on those road pieces: {'maxspeed': 7854, 'surface': 11094, 'smoothness': 413, 'lanes': 4958, 'curve': 0, 'tracktype': 1475}. `curve=*` values: {}. Top `surface` values: {'asphalt': 8433, 'paved': 937, 'gravel': 757, 'concrete': 517, 'unpaved': 248, 'dirt': 147, 'compacted': 29, 'ground': 19, 'fine_gravel': 3, 'chipseal': 2, 'paving_stones': 1, 'metal': 1}. Top `maxspeed` values: {'20 mph': 2090, '25 mph': 1538, '45 mph': 823, '35 mph': 771, '30 mph': 669, '40 mph': 521, '55 mph': 422, '70 mph': 338, '65 mph': 299, '50 mph': 100, '75 mph': 92, '60 mph': 78}.

Tag coverage by OSM highway class (percent of ways):

| highway | ways | km | maxspeed_pct | surface_pct | smoothness_n | lanes_n | curve_tag_n |
|---|---|---|---|---|---|---|---|
| residential | 19,508 | 6,974.4 | 16.4 | 29.1 | 245 | 723 | 0 |
| tertiary | 2,563 | 1,431.1 | 55.4 | 65.4 | 43 | 1,235 | 0 |
| secondary | 1,604 | 784.1 | 78.6 | 76.9 | 57 | 1,101 | 0 |
| track | 1,124 | 387.8 | 0.1 | 7.6 | 2 | 0 | 0 |
| unclassified | 926 | 660.6 | 13.2 | 65.3 | 6 | 57 | 0 |
| primary | 603 | 244.7 | 96.2 | 94.0 | 12 | 459 | 0 |
| trunk | 491 | 179.3 | 97.4 | 98.8 | 22 | 484 | 0 |
| motorway_link | 453 | 78.6 | 74.4 | 75.9 | 19 | 396 | 0 |
| motorway | 374 | 262.8 | 93.9 | 72.7 | 6 | 374 | 0 |
| trunk_link | 62 | 3.1 | 59.7 | 79.0 | 0 | 42 | 0 |
| primary_link | 61 | 5.0 | 60.7 | 67.2 | 0 | 42 | 0 |
| secondary_link | 50 | 2.8 | 28.0 | 44.0 | 1 | 20 | 0 |
| tertiary_link | 46 | 2.6 | 32.6 | 60.9 | 0 | 24 | 0 |
| living_street | 13 | 2.5 | 30.8 | 30.8 | 0 | 1 | 0 |

Length-weighted coverage on OSM roads matched (≤15 m, 50 m sample points) to ACF centerlines, split by ACF surface and class group (210,208 sample points, 94.1% matched to any ACF line):

| ACF_group | ACF_surface | osm_km | pct_with_maxspeed | pct_with_surface_tag | osm_surface_agrees_pct_of_tagged |
|---|---|---|---|---|---|
| ACF County | Paved | 1,515.3 | 10.6 | 40.7 | 91.6 |
| ACF County | Unpaved | 1,887.5 | 1.0 | 54.2 | 96.0 |
| ACF other class | Paved | 6,300.7 | 39.7 | 45.7 | 98.4 |
| ACF other class | Unpaved | 655.1 | 1.1 | 32.0 | 78.0 |

OSM-only proxy for county roads (tertiary/unclassified/residential/track): 24,121 ways, maxspeed on 19.7%, surface on 33.4%. Only unclassified+track (2,050 ways): maxspeed 6.0%, surface 33.7%.

Detected R<600 ft curves vs OSM (nearest drivable OSM way ≤20 m): matched 91.5%; with `maxspeed` 12.4%; with `surface` 32.4%; County-class paved (n=3208) maxspeed 7.7%; County-class unpaved (n=4829) maxspeed 0.6%.


## 8. Posted speed limits and statute

* ACF layer 18: **no speed-limit attribute** (see field list). OSM: coverage numbers above (`maxspeed`).
* Ark. Code Ann. § 27-51-216(b): a county judge may set speed limits on county roads; **if none is set, the limit is 40 mph** on the county road ("county road" = public road that is not a state highway, interstate or city street). Speeding >15 mph over is a Class C misdemeanor (§ 27-51-216(c)(2)). Traffic-control devices must conform to the MUTCD adopted by the State Highway Commission (§ 27-51-216(d)). Enacted by Acts 2007, No. 667 (before that, 65 mph per the AAC road-law guide).
* Ark. Code Ann. § 27-51-201(a) (reasonable-and-prudent rule) and (d) (reduce speed approaching/going around a curve, narrow or winding roadway) apply regardless of any limit. As retrieved (Justia 2025 / Syfert, effective 7/1/2020 version), § 27-51-201(c) no longer contains a general 60/65 mph rural number for cars: it lists 30 mph urban district, 50 mph trucks ≥1.5 ton "in other locations", and 30 mph oversize.
* **App assumption when no posted limit exists on a county road: 40 mph (§ 27-51-216(b)(2))**, labelled as a statutory default; for state/city roads there is no equivalent simple default — treat as unknown and do not display a limit. A posted/OSM `maxspeed` overrides it. Statute text was obtained from secondary publishers (Justia/FindLaw/Syfert/AAC guide) because direct fetch of Justia returned HTTP 403; verify against the official Arkansas Code before shipping.


## 9. Licensing

* **Arkansas GIS Office ROADS_ACF**: the ArcGIS Hub item metadata (item `3c16bf0bbd7547ffb735fa2dba4cdcfc`, "Road Centerline File", source 'Arkansas GIS Office') has `license: none`, empty `licenseInfo`, empty `accessInformation`; the MapServer has empty `copyrightText`. I found **no explicit license text** for this layer, so the terms are unstated; do not assume CC0/public-domain. Get written confirmation from the Arkansas GIS Office (and check the portal's disclaimer page) before commercial redistribution. The item description states the ACF standard requires ≤10 m horizontal accuracy (NSSDA).
* **OpenStreetMap**: ODbL 1.0 — © OpenStreetMap contributors. Required: visible attribution ("© OpenStreetMap contributors" with link to https://www.openstreetmap.org/copyright), share-alike for a publicly used *derived database* (e.g. a curves layer built with OSM tags must be offered under ODbL; a 'Produced Work' such as a map image only needs attribution), keep ODbL notice, and keep it open (no technical restrictions). Geofabrik extracts carry the same license. Mixed ACF+OSM data may create a share-alike obligation for the merged database — the exported `osm_*` columns in curves.geojson are OSM-derived.


## 10. Run info

Timings (cumulative seconds since start): {"pbf downloaded/cached": 0.0, "centerlines fetched/cached": 1.6, "prep": 2.0, "vertex spacing": 2.2, "chains built (21462 chains from 48303 segments)": 4.6, "detection main": 11.9, "sensitivity runs": 35.8, "stats": 36.7, "speeds": 36.8, "osm analysis": 42.6, "synthetic validation": 43.7, "examples": 43.9, "geojson written": 46.0}

Fetch failures/retries logged: []
