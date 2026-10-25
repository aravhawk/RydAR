#!/usr/bin/env python3
"""
Curve-crash audit for Arkansas 3rd Congressional District (AR-3) using NHTSA FARS.

Everything is downloaded and computed from the raw files; no number is typed in by hand.

Sources (all downloaded by this script):
  FARS national CSV zips: https://static.nhtsa.gov/nhtsa/downloads/FARS/<YEAR>/National/FARS<YEAR>NationalCSV.zip
  Census county population estimates:
    2020-2024: https://www2.census.gov/programs-surveys/popest/datasets/2020-2024/counties/totals/co-est2024-alldata.csv
    2010-2019: https://www2.census.gov/programs-surveys/popest/datasets/2010-2019/counties/totals/co-est2019-alldata.csv

Usage: python3 compute.py          (re-runs everything; reuses already-downloaded files)
"""
import io, os, sys, zipfile, urllib.request, urllib.error, glob
import numpy as np
import pandas as pd
from scipy import stats

OUT = "/tmp/curveaudit_fars"
RAW = f"{OUT}/raw"
os.makedirs(RAW, exist_ok=True)
YEARS_TRY = list(range(2015, 2026))          # 2025 is probed; it 404s on 2026-10-24
FARS_URL = "https://static.nhtsa.gov/nhtsa/downloads/FARS/{y}/National/FARS{y}NationalCSV.zip"
CENSUS = {
    "2020-2024": "https://www2.census.gov/programs-surveys/popest/datasets/2020-2024/counties/totals/co-est2024-alldata.csv",
    "2010-2019": "https://www2.census.gov/programs-surveys/popest/datasets/2010-2019/counties/totals/co-est2019-alldata.csv",
}
AR_STATE = 5
AR3 = {7: "Benton", 15: "Carroll", 33: "Crawford", 87: "Madison", 143: "Washington"}
SEB = {131: "Sebastian"}
UA = {"User-Agent": "Mozilla/5.0 (curveaudit student brief)"}

pd.set_option("display.width", 250, "display.max_columns", 50, "display.max_rows", 500)


# ----------------------------------------------------------------------------- download
def fetch(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 1000:
        return 200
    req = urllib.request.Request(url, headers=UA)
    try:
        with urllib.request.urlopen(req, timeout=300) as r, open(dest, "wb") as f:
            f.write(r.read())
        return 200
    except urllib.error.HTTPError as e:
        return e.code


avail = []
for y in YEARS_TRY:
    dest = f"{RAW}/FARS{y}.zip"
    code = fetch(FARS_URL.format(y=y), dest)
    avail.append({"year": y, "url": FARS_URL.format(y=y), "http_status": code,
                  "bytes": os.path.getsize(dest) if code == 200 and os.path.exists(dest) else 0})
    if code == 200 and not os.path.isdir(f"{RAW}/{y}"):
        with zipfile.ZipFile(dest) as z:
            z.extractall(f"{RAW}/{y}")
avail = pd.DataFrame(avail)
avail.to_csv(f"{OUT}/00_file_availability.csv", index=False)
YEARS = [int(y) for y in avail[avail.http_status == 200].year]
print("FARS years downloadable:", YEARS)
print(avail.to_string(index=False))

for k, u in CENSUS.items():
    fetch(u, f"{RAW}/co-est-{k}.csv")


# ----------------------------------------------------------------------------- load
def find(y, name):
    for f in glob.glob(f"{RAW}/{y}/**/*", recursive=True):
        if os.path.basename(f).lower() == name:
            return f
    raise FileNotFoundError((y, name))


def rd(y, name, usecols=None):
    f = find(y, name)
    # NOTE: the 2021 and 2022 accident files start with a UTF-8 BOM; 'utf-8-sig' strips it
    # (otherwise STATE is read as 'ï»¿STATE' and every state filter silently returns nothing).
    for enc in ("utf-8-sig", "latin1"):
        try:
            d = pd.read_csv(f, encoding=enc, low_memory=False)
            break
        except UnicodeDecodeError:
            continue
    d.columns = [c.replace("\ufeff", "").replace("ï»¿", "").strip() for c in d.columns]
    if usecols:
        d = d[[c for c in usecols if c in d.columns]]
    d["FARSYEAR"] = y
    return d


ACC_COLS = ["STATE", "ST_CASE", "COUNTY", "COUNTYNAME", "YEAR", "FATALS", "VE_TOTAL", "VE_FORMS", "PEDS",
            "PERNOTMVIT", "ROUTE", "RUR_URB", "RD_OWNER", "FUNC_SYS", "REL_ROAD", "LGT_COND", "WEATHER",
            "MAN_COLL", "HARM_EV", "TWAY_ID"]
VEH_COLS = ["STATE", "ST_CASE", "VEH_NO", "VALIGN", "VPAVETYP", "VSURCOND", "VTRAFWAY", "SPEEDREL", "ROLLOVER",
            "HARM_EV", "PCRASH5", "P_CRASH2", "DEATHS"]
A = pd.concat([rd(y, "accident.csv", ACC_COLS) for y in YEARS], ignore_index=True)
V = pd.concat([rd(y, "vehicle.csv", VEH_COLS) for y in YEARS], ignore_index=True)
assert A.STATE.notna().all() and V.STATE.notna().all(), "STATE missing -> BOM problem"
A["STATE"] = A.STATE.astype(int)
A["COUNTY"] = A.COUNTY.astype(int)
assert (A.YEAR == A.FARSYEAR).all()
print("\nNational fatal crashes per year (rows in accident file):")
print(A.groupby("FARSYEAR").size().to_string())

# county-name sanity check (COUNTYNAME exists 2020+ only)
chk = A[(A.STATE == AR_STATE) & (A.COUNTY.isin(list(AR3) + list(SEB))) & A.COUNTYNAME.notna()]
print("\nCOUNTY code -> COUNTYNAME check (2020+):")
print(chk.groupby(["COUNTY", "COUNTYNAME"]).size().to_string())

# ----------------------------------------------------------------------------- crash-level derived flags
# Vehicle-level -> crash-level (any vehicle in the crash)
V["curve_v"] = V.VALIGN.isin([2, 3, 4])
V["straight_v"] = V.VALIGN == 1
V["align_known_v"] = V.VALIGN.isin([1, 2, 3, 4])
V["rollover_v"] = V.ROLLOVER.isin([1, 2, 3, 9])         # 2015-2021: 1,2,9 ; 2022+: 3 (8 = N/A)
V["speed_v"] = V.SPEEDREL.isin([2, 3, 4, 5])             # racing / exceeded limit / too fast / unspecified
V["wet_v"] = V.VSURCOND == 2
V["nondry_v"] = V.VSURCOND.isin([2, 3, 4, 6, 7, 10])     # wet, snow, ice, standing water, oil, slush
V["unpaved_type_v"] = V.VPAVETYP.isin([4, 5])            # 4 Slag/Gravel/Stone ; 5 Dirt
V["gravel_cond_v"] = V.VSURCOND == 11                    # Mud, Dirt or Gravel (surface *condition*)
V["pavetyp_known_v"] = V.VPAVETYP.isin([1, 2, 3, 4, 5, 7])
V["departed_v"] = V.PCRASH5.isin([4, 5])                 # Departed roadway / Remained off roadway
V["undivided_v"] = V.VTRAFWAY == 1
V["curve_first_v"] = V.curve_v & (V.VEH_NO == 1)

g = V.groupby(["FARSYEAR", "ST_CASE"])
C = pd.DataFrame({
    "curve_any": g.curve_v.any(), "straight_any": g.straight_v.any(), "align_known": g.align_known_v.any(),
    "rollover_any": g.rollover_v.any(), "speed_any": g.speed_v.any(), "wet_any": g.wet_v.any(),
    "nondry_any": g.nondry_v.any(), "unpaved_type_any": g.unpaved_type_v.any(),
    "gravel_cond_any": g.gravel_cond_v.any(), "pavetyp_known_any": g.pavetyp_known_v.any(),
    "departed_any": g.departed_v.any(), "undivided_any": g.undivided_v.any(),
    "veh1_valign": g[["VEH_NO", "VALIGN"]].apply(lambda d: d.loc[d.VEH_NO.idxmin(), "VALIGN"]),
    "n_veh_records": g.size(),
}).reset_index()
# crashes with mixed curve/straight coding between vehicles
C["mixed_align"] = C.curve_any & C.straight_any
C["veh1_curve"] = C.veh1_valign.isin([2, 3, 4])
X = A.merge(C, on=["FARSYEAR", "ST_CASE"], how="left")
assert X.curve_any.notna().all()
for c in [c for c in C.columns if c not in ("FARSYEAR", "ST_CASE", "veh1_valign", "n_veh_records")]:
    X[c] = X[c].astype(bool)

X["single_veh"] = (X.VE_FORMS == 1) & (X.PERNOTMVIT == 0)
X["ror_A"] = X.single_veh & X.REL_ROAD.isin([2, 3, 4, 6, 8])      # 1st harmful event off the roadway
X["night"] = X.LGT_COND.isin([2, 3, 6])                              # Dark (lighted/unlighted/unknown lighting)
X["rain"] = X.WEATHER == 2
route_map = {1: "Interstate", 2: "US Highway", 3: "State Highway", 4: "County Road",
             5: "Local Street", 6: "Local Street", 7: "Local Street"}
X["route_cat"] = X.ROUTE.map(route_map).fillna("Other/Not signed/Unknown")
owner_map = {1: "State Highway Agency (ARDOT)", 31: "State Highway Agency (ARDOT)", 2: "County Highway Agency",
             3: "Town/Township Agency", 4: "City/Municipal Agency"}
X["owner_cat"] = X.RD_OWNER.map(owner_map).fillna("Other/Not in inventory/Unknown")
X["rural_cat"] = X.RUR_URB.map({1: "Rural", 2: "Urban"}).fillna("Other/Unknown")


def geo_mask(df, geo):
    if geo in AR3.values():
        c = [k for k, v in AR3.items() if v == geo][0]
        return (df.STATE == AR_STATE) & (df.COUNTY == c)
    return {
        "AR-3 five-county total": (df.STATE == AR_STATE) & df.COUNTY.isin(list(AR3)),
        "Sebastian (separate, NOT in AR-3)": (df.STATE == AR_STATE) & (df.COUNTY == 131),
        "Arkansas statewide": df.STATE == AR_STATE,
        "United States (50 states + DC)": df.STATE > 0,
    }[geo]


GEOS = list(AR3.values()) + ["AR-3 five-county total", "Sebastian (separate, NOT in AR-3)", "Arkansas statewide",
                             "United States (50 states + DC)"]
AR6 = X[(X.STATE == AR_STATE) & X.COUNTY.isin(list(AR3) + list(SEB))].copy()
AR6["County"] = AR6.COUNTY.map({**AR3, **SEB})


def fmt(n, d, flag=True):
    s = f"{n}/{d} ({100 * n / d:.1f}%)" if d else f"{n}/0 (n/a)"
    if flag and (n < 10 or d < 10):
        s += " †"
    return s


# ----------------------------------------------------------------------------- 1. crashes & deaths
print("\n" + "=" * 100 + "\nTABLE 1  Fatal crashes and deaths by year and county (FARS accident file; deaths = sum of FATALS)")
t1 = AR6.groupby(["FARSYEAR", "County"]).agg(fatal_crashes=("ST_CASE", "size"), deaths=("FATALS", "sum")).reset_index()
full = pd.MultiIndex.from_product([YEARS, list(AR3.values()) + ["Sebastian"]], names=["FARSYEAR", "County"])
t1 = t1.set_index(["FARSYEAR", "County"]).reindex(full, fill_value=0).reset_index()
s5 = t1[t1.County.isin(AR3.values())].groupby("FARSYEAR")[["fatal_crashes", "deaths"]].sum().reset_index()
s5["County"] = "AR-3 five-county sum"
t1_long = pd.concat([t1, s5], ignore_index=True)
t1_long.to_csv(f"{OUT}/t1_fatal_crashes_deaths_long.csv", index=False)
order = list(AR3.values()) + ["AR-3 five-county sum", "Sebastian"]
for m in ["fatal_crashes", "deaths"]:
    w = t1_long.pivot(index="County", columns="FARSYEAR", values=m).reindex(order)
    w["TOTAL"] = w.sum(axis=1)
    w.to_csv(f"{OUT}/t1_{m}_by_year_wide.csv")
    print(f"\n{m}:\n{w.to_string()}")

# cross-check deaths with the person file (INJ_SEV == 4 = Fatal injury)
P = pd.concat([rd(y, "person.csv", ["STATE", "ST_CASE", "INJ_SEV", "COUNTY"]) for y in YEARS], ignore_index=True)
Pk = P[(P.STATE == AR_STATE) & P.COUNTY.isin(list(AR3) + list(SEB)) & (P.INJ_SEV == 4)]
pchk = Pk.groupby("COUNTY").size().rename("person_file_INJ_SEV4")
fchk = AR6.groupby("COUNTY").FATALS.sum().rename("accident_file_FATALS")
chk = pd.concat([fchk, pchk], axis=1)
chk.index = chk.index.map({**AR3, **SEB})
print("\nCross-check of deaths, accident FATALS vs person file INJ_SEV=4 (all years):\n", chk.to_string())
chk.to_csv(f"{OUT}/t1_deaths_crosscheck_person_file.csv")

# ----------------------------------------------------------------------------- 2. curve share
print("\n" + "=" * 100 + "\nTABLE 2  Curve share of fatal crashes (crash is 'curve' if ANY vehicle has VALIGN in {2 Curve Right, 3 Curve Left, 4 Curve-Unknown Dir})")
rows = []
for geo in GEOS:
    d = X[geo_mask(X, geo)]
    N = len(d)
    rows.append({
        "geography": geo, "years": f"{YEARS[0]}-{YEARS[-1]}", "all_fatal_crashes": N,
        "curve_crashes": int(d.curve_any.sum()),
        "straight_only_crashes": int((d.straight_any & ~d.curve_any).sum()),
        "alignment_not_determinable": int((~d.align_known).sum()),
        "crashes_with_known_alignment": int(d.align_known.sum()),
        "curve_share_of_ALL_crashes_pct": round(100 * d.curve_any.mean(), 2),
        "curve_share_of_KNOWN_alignment_pct": round(100 * d.curve_any.sum() / max(d.align_known.sum(), 1), 2),
        "veh1_curve_crashes": int(d.veh1_curve.sum()),
        "veh1_curve_share_of_ALL_pct": round(100 * d.veh1_curve.mean(), 2),
        "crashes_where_vehicles_disagree_curve_vs_straight": int(d.mixed_align.sum()),
    })
t2 = pd.DataFrame(rows)
t2.to_csv(f"{OUT}/t2_curve_share_summary.csv", index=False)
print(t2.T.to_string())

# per-year curve share for AR-3 total vs US
ry = []
for geo in ["AR-3 five-county total", "Arkansas statewide", "United States (50 states + DC)"]:
    for y in YEARS:
        d = X[geo_mask(X, geo) & (X.FARSYEAR == y)]
        ry.append({"geography": geo, "year": y, "all_fatal_crashes": len(d), "curve_crashes": int(d.curve_any.sum()),
                   "curve_share_all_pct": round(100 * d.curve_any.mean(), 1),
                   "known_alignment": int(d.align_known.sum()),
                   "curve_share_known_pct": round(100 * d.curve_any.sum() / max(d.align_known.sum(), 1), 1)})
t2y = pd.DataFrame(ry)
t2y.to_csv(f"{OUT}/t2_curve_share_by_year.csv", index=False)
print("\nCurve share by year:\n", t2y.pivot(index="year", columns="geography", values="curve_share_all_pct").to_string())
# per county per year curve counts
cy = AR6.groupby(["FARSYEAR", "County"]).agg(fatal_crashes=("ST_CASE", "size"), curve_crashes=("curve_any", "sum")).reset_index()
cy.to_csv(f"{OUT}/t2_curve_counts_county_year.csv", index=False)

# Table 2b: significance and rural-only comparison (rurality is a confounder: curves are more common on rural roads)
print("\nTABLE 2b  Comparison tests (share of ALL fatal crashes that are curve crashes)")
rows = []
def wilson(k, n, z=1.96):
    p = k / n; den = 1 + z * z / n
    c = (p + z * z / (2 * n)) / den; h = z * np.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return 100 * (c - h), 100 * (c + h)
def cmp(label, a, b, la, lb):
    ka, na, kb, nb = int(a.curve_any.sum()), len(a), int(b.curve_any.sum()), len(b)
    chi2, p, _, _ = stats.chi2_contingency([[ka, na - ka], [kb, nb - kb]], correction=False)
    la_lo, la_hi = wilson(ka, na); lb_lo, lb_hi = wilson(kb, nb)
    rows.append({"comparison": label, f"A": la, "A_n": f"{ka}/{na}", "A_pct": round(100 * ka / na, 1),
                 "A_wilson95": f"{la_lo:.1f}-{la_hi:.1f}", "B": lb, "B_n": f"{kb}/{nb}", "B_pct": round(100 * kb / nb, 1),
                 "B_wilson95": f"{lb_lo:.1f}-{lb_hi:.1f}", "chi2_p_value": float(f"{p:.3g}")})
ar3m, usm, arm = geo_mask(X, "AR-3 five-county total"), geo_mask(X, "United States (50 states + DC)"), geo_mask(X, "Arkansas statewide")
cmp("AR-3 vs US, all crashes", X[ar3m], X[usm], "AR-3", "US")
cmp("AR-3 vs Arkansas statewide, all crashes", X[ar3m], X[arm], "AR-3", "AR")
cmp("AR-3 RURAL vs US RURAL", X[ar3m & (X.RUR_URB == 1)], X[usm & (X.RUR_URB == 1)], "AR-3 rural", "US rural")
cmp("AR-3 URBAN vs US URBAN", X[ar3m & (X.RUR_URB == 2)], X[usm & (X.RUR_URB == 2)], "AR-3 urban", "US urban")
cmp("AR-3 RURAL vs Arkansas RURAL", X[ar3m & (X.RUR_URB == 1)], X[arm & (X.RUR_URB == 1)], "AR-3 rural", "AR rural")
cmp("Carroll+Madison vs Benton+Washington+Crawford", X[geo_mask(X, "Carroll") | geo_mask(X, "Madison")],
    X[geo_mask(X, "Benton") | geo_mask(X, "Washington") | geo_mask(X, "Crawford")], "Carroll+Madison", "Other 3 AR-3")
cmp("Carroll vs US", X[geo_mask(X, "Carroll")], X[usm], "Carroll", "US")
cmp("Madison vs US", X[geo_mask(X, "Madison")], X[usm], "Madison", "US")
t2b = pd.DataFrame(rows)
t2b.to_csv(f"{OUT}/t2b_curve_share_comparisons.csv", index=False)
print(t2b.to_string(index=False))
# rural-only / urban-only curve share by geography
rr = []
for geo in GEOS:
    for nm, code in [("Rural", 1), ("Urban", 2)]:
        d = X[geo_mask(X, geo) & (X.RUR_URB == code)]
        rr.append({"geography": geo, "RUR_URB": nm, "all_fatal_crashes": len(d), "curve_crashes": int(d.curve_any.sum()),
                   "curve_share_pct": round(100 * d.curve_any.mean(), 1) if len(d) else np.nan})
t2c = pd.DataFrame(rr)
t2c.to_csv(f"{OUT}/t2c_curve_share_rural_urban.csv", index=False)
print("\nCurve share within rural / urban fatal crashes:\n", t2c.to_string(index=False))

# ----------------------------------------------------------------------------- 3. curve profile
print("\n" + "=" * 100 + "\nTABLE 3  Profile of CURVE crashes (denominator = curve crashes in that geography; † = count or denominator < 10 => weak)")
prof_rows = []


def add(geo, label, num, den, formula):
    prof_rows.append({"geography": geo, "measure": label, "n": int(num), "denominator": int(den),
                      "share_pct": round(100 * num / den, 1) if den else np.nan,
                      "n_or_denom_below_10": bool(num < 10 or den < 10), "formula": formula})


for geo in GEOS:
    d = X[geo_mask(X, geo) & X.curve_any]
    D = len(d)
    add(geo, "Curve crashes (denominator)", D, D, "n curve crashes")
    add(geo, "Single-vehicle, no non-motorist (VE_FORMS=1 & PERNOTMVIT=0)", d.single_veh.sum(), D, "/ curve crashes")
    add(geo, "Single-vehicle run-off-road (above & REL_ROAD in 2,3,4,6,8)", d.ror_A.sum(), D, "/ curve crashes")
    sv = d.single_veh.sum()
    add(geo, "  ...run-off-road as share of SINGLE-VEHICLE curve crashes", d.ror_A.sum(), sv, "/ single-vehicle curve crashes")
    add(geo, "Any vehicle PCRASH5 = Departed/Remained off roadway", d.departed_any.sum(), D, "/ curve crashes")
    add(geo, "Rollover (any vehicle, ROLLOVER in 1,2,3,9)", d.rollover_any.sum(), D, "/ curve crashes")
    add(geo, "Night: LGT_COND in Dark-lighted/unlighted/unknown (3,2,6)", d.night.sum(), D, "/ curve crashes")
    add(geo, "Wet surface (any vehicle VSURCOND=2)", d.wet_any.sum(), D, "/ curve crashes")
    add(geo, "Non-dry surface (VSURCOND 2,3,4,6,7,10)", d.nondry_any.sum(), D, "/ curve crashes")
    add(geo, "Rain (WEATHER=2)", d.rain.sum(), D, "/ curve crashes")
    add(geo, "Speeding-related (any vehicle SPEEDREL in 2,3,4,5)", d.speed_any.sum(), D, "/ curve crashes")
    for rc in ["Interstate", "US Highway", "State Highway", "County Road", "Local Street", "Other/Not signed/Unknown"]:
        add(geo, f"ROUTE: {rc}", (d.route_cat == rc).sum(), D, "/ curve crashes")
    for rc in ["Rural", "Urban", "Other/Unknown"]:
        add(geo, f"RUR_URB: {rc}", (d.rural_cat == rc).sum(), D, "/ curve crashes")
    add(geo, "Undivided two-way (any vehicle VTRAFWAY=1)", d.undivided_any.sum(), D, "/ curve crashes")
    for oc in ["State Highway Agency (ARDOT)", "County Highway Agency", "City/Municipal Agency", "Town/Township Agency",
               "Other/Not in inventory/Unknown"]:
        add(geo, f"RD_OWNER: {oc}", (d.owner_cat == oc).sum(), D, "/ curve crashes")
t3 = pd.DataFrame(prof_rows)
t3.to_csv(f"{OUT}/t3_curve_crash_profile.csv", index=False)
piv = t3.assign(cell=lambda z: [fmt(n, d_, True) for n, d_ in zip(z.n, z.denominator)]).pivot(
    index="measure", columns="geography", values="cell")
measure_order = list(dict.fromkeys(t3.measure))
piv = piv.reindex(measure_order)[GEOS]
piv.to_csv(f"{OUT}/t3_curve_crash_profile_wide.csv")
print(piv.to_string())

# ----------------------------------------------------------------------------- 4. deaths by route
print("\n" + "=" * 100 + "\nTABLE 4  DEATHS (sum of FATALS) by ROUTE signing category, all fatal crashes, " f"{YEARS[0]}-{YEARS[-1]}")
cats = ["Interstate", "US Highway", "State Highway", "County Road", "Local Street", "Other/Not signed/Unknown"]
t4 = AR6.pivot_table(index="County", columns="route_cat", values="FATALS", aggfunc="sum", fill_value=0).reindex(columns=cats, fill_value=0)
t4 = t4.reindex(list(AR3.values()) + ["Sebastian"])
t4.loc["AR-3 five-county total"] = t4.loc[list(AR3.values())].sum()
t4 = t4.reindex(list(AR3.values()) + ["AR-3 five-county total", "Sebastian"])
t4["TOTAL_deaths"] = t4.sum(axis=1)
t4["State-system (Interstate+US+State)"] = t4[["Interstate", "US Highway", "State Highway"]].sum(axis=1)
t4["Non-state (County+Local)"] = t4[["County Road", "Local Street"]].sum(axis=1)
t4["pct_County+Local"] = (100 * t4["Non-state (County+Local)"] / t4.TOTAL_deaths).round(1)
t4["pct_State-system"] = (100 * t4["State-system (Interstate+US+State)"] / t4.TOTAL_deaths).round(1)
t4.to_csv(f"{OUT}/t4_deaths_by_route_county.csv")
print(t4.to_string())
# local street split, and per year for the 5-county total
t4b = AR6[AR6.COUNTY.isin(list(AR3))].assign(
    route_detail=lambda z: z.ROUTE.map({1: "Interstate", 2: "US Highway", 3: "State Highway", 4: "County Road",
                                        5: "Local-Township", 6: "Local-Municipal", 7: "Local-Frontage"}).fillna("Other/Not signed/Unknown")
).pivot_table(index="FARSYEAR", columns="route_detail", values="FATALS", aggfunc="sum", fill_value=0)
t4b["TOTAL"] = t4b.sum(axis=1)
t4b.loc["ALL YEARS"] = t4b.sum()
t4b.to_csv(f"{OUT}/t4_deaths_by_route_detail_ar3_by_year.csv")
print("\nAR-3 five-county deaths by detailed ROUTE code and year:\n", t4b.to_string())
# By road OWNER (independent of ROUTE signing)
ocats = ["State Highway Agency (ARDOT)", "County Highway Agency", "City/Municipal Agency", "Town/Township Agency", "Other/Not in inventory/Unknown"]
t4c = AR6.pivot_table(index="County", columns="owner_cat", values="FATALS", aggfunc="sum", fill_value=0).reindex(columns=ocats, fill_value=0)
t4c = t4c.reindex(list(AR3.values()) + ["Sebastian"])
t4c.loc["AR-3 five-county total"] = t4c.loc[list(AR3.values())].sum()
t4c = t4c.reindex(list(AR3.values()) + ["AR-3 five-county total", "Sebastian"])
t4c["TOTAL_deaths"] = t4c.sum(axis=1)
t4c["pct_not_ARDOT_owned"] = (100 * (t4c.TOTAL_deaths - t4c["State Highway Agency (ARDOT)"]) / t4c.TOTAL_deaths).round(1)
t4c.to_csv(f"{OUT}/t4_deaths_by_road_owner_county.csv")
print("\nDeaths by RD_OWNER (road ownership; cross-check on ROUTE):\n", t4c.to_string())
xt = pd.crosstab(AR6[AR6.COUNTY.isin(list(AR3))].route_cat, AR6[AR6.COUNTY.isin(list(AR3))].owner_cat, values=AR6[AR6.COUNTY.isin(list(AR3))].FATALS, aggfunc="sum").fillna(0).astype(int)
xt.to_csv(f"{OUT}/t4_route_vs_owner_crosstab_ar3_deaths.csv")
print("\nCrosstab of deaths in AR-3: ROUTE (rows) vs RD_OWNER (columns) -> shows where the two codings disagree:\n", xt.to_string())

# ----------------------------------------------------------------------------- 5. rates per 100k
print("\n" + "=" * 100 + "\nTABLE 5  Deaths per 100,000 residents (FARS deaths / Census Vintage population estimate)")
c24 = pd.read_csv(f"{RAW}/co-est-2020-2024.csv", encoding="latin1")
c19 = pd.read_csv(f"{RAW}/co-est-2010-2019.csv", encoding="latin1")
pop = {}
for df in (c19, c24):
    ar = df[(df.STATE == AR_STATE) & (df.COUNTY > 0)]
    for _, r in ar.iterrows():
        for col in [c for c in df.columns if c.startswith("POPESTIMATE")]:
            pop[(int(r.COUNTY), int(col[-4:]))] = int(r[col])   # later file (2020-24 vintage) overrides 2020
popdf = pd.DataFrame([{"COUNTY": k[0], "year": k[1], "pop": v} for k, v in pop.items() if k[1] in YEARS])
popdf.to_csv(f"{OUT}/t5_census_population_used.csv", index=False)
names = {**AR3, **SEB}
ard = A[A.STATE == AR_STATE].groupby(["FARSYEAR", "COUNTY"]).FATALS.sum().reset_index().rename(columns={"FARSYEAR": "year"})


def rate_block(yrs, label):
    out = []
    for cty, nm in {**AR3, **SEB}.items():
        dths = int(ard[(ard.COUNTY == cty) & ard.year.isin(yrs)].FATALS.sum())
        py = int(popdf[(popdf.COUNTY == cty) & popdf.year.isin(yrs)]["pop"].sum())
        lo = stats.chi2.ppf(0.025, 2 * dths) / 2 if dths > 0 else 0.0
        hi = stats.chi2.ppf(0.975, 2 * (dths + 1)) / 2
        out.append({"period": label, "county": nm, "deaths": dths, "person_years": py,
                    "pop_latest_year": int(popdf[(popdf.COUNTY == cty) & (popdf.year == max(yrs))]["pop"].iloc[0]),
                    "deaths_per_100k": round(1e5 * dths / py, 2),
                    "ci95_lo": round(1e5 * lo / py, 2), "ci95_hi": round(1e5 * hi / py, 2)})
    d = pd.DataFrame(out)
    # AR-3 five-county pooled
    k = int(d[d.county.isin(AR3.values())].deaths.sum()); py = int(d[d.county.isin(AR3.values())].person_years.sum())
    d.loc[len(d)] = {"period": label, "county": "AR-3 five-county pooled", "deaths": k, "person_years": py,
                     "pop_latest_year": int(d[d.county.isin(AR3.values())].pop_latest_year.sum()),
                     "deaths_per_100k": round(1e5 * k / py, 2),
                     "ci95_lo": round(1e5 * (stats.chi2.ppf(0.025, 2 * k) / 2) / py, 2),
                     "ci95_hi": round(1e5 * (stats.chi2.ppf(0.975, 2 * (k + 1)) / 2) / py, 2)}
    b = d[d.county == "Benton"].iloc[0]
    ratios, rlo, rhi = [], [], []
    for _, r in d.iterrows():
        x, y_ = r.deaths, b.deaths
        ratio = (x / r.person_years) / (y_ / b.person_years)
        # exact conditional (binomial) CI for the rate ratio
        n = x + y_
        if x > 0 and y_ > 0:
            plo = stats.beta.ppf(0.025, x, y_ + 1); phi = stats.beta.ppf(0.975, x + 1, y_)
            f = lambda p: (p / (1 - p)) * (b.person_years / r.person_years)
            lo_, hi_ = f(plo), f(phi)
        else:
            lo_, hi_ = np.nan, np.nan
        ratios.append(round(ratio, 2)); rlo.append(round(lo_, 2)); rhi.append(round(hi_, 2))
    d["rate_ratio_vs_Benton"] = ratios; d["ratio_ci95_lo"] = rlo; d["ratio_ci95_hi"] = rhi
    return d


t5 = pd.concat([rate_block([2024], "2024"), rate_block([2023], "2023"), rate_block([2023, 2024], "2023+2024 pooled"),
                rate_block(YEARS, f"{YEARS[0]}-{YEARS[-1]} pooled")], ignore_index=True)
t5.to_csv(f"{OUT}/t5_deaths_per_100k.csv", index=False)
print(t5.to_string(index=False))

# ----------------------------------------------------------------------------- 6. unpaved / gravel
print("\n" + "=" * 100 + "\nTABLE 6  Unpaved / gravel indicators (Vehicle file VPAVETYP, VSURCOND) - fatal crashes, "
      f"{YEARS[0]}-{YEARS[-1]}")
rows = []
for geo in GEOS:
    d = X[geo_mask(X, geo)]
    N = len(d)
    rows.append({"geography": geo, "all_fatal_crashes": N,
                 "crashes_pavement_type_known (VPAVETYP 1,2,3,4,5,7 any vehicle)": int(d.pavetyp_known_any.sum()),
                 "unpaved_VPAVETYP_4_gravel_or_5_dirt (any vehicle)": int(d.unpaved_type_any.sum()),
                 "VSURCOND_11_mud_dirt_gravel (any vehicle)": int(d.gravel_cond_any.sum()),
                 "either_indicator": int((d.unpaved_type_any | d.gravel_cond_any).sum())})
t6 = pd.DataFrame(rows)
t6.to_csv(f"{OUT}/t6_unpaved_gravel_counts.csv", index=False)
print(t6.T.to_string())
# vehicle-level code distribution in AR-3 and coverage
Vk = V.merge(A[["FARSYEAR", "ST_CASE", "COUNTY"]], on=["FARSYEAR", "ST_CASE"])
Vk3 = Vk[(Vk.STATE == AR_STATE) & Vk.COUNTY.isin(list(AR3))]
t6b = Vk3.groupby(["VPAVETYP"]).size().rename("AR3_vehicle_records").to_frame()
t6b["share_pct"] = (100 * t6b.AR3_vehicle_records / t6b.AR3_vehicle_records.sum()).round(1)
t6b.to_csv(f"{OUT}/t6_vpavetyp_distribution_ar3.csv")
print("\nAR-3 vehicle records by VPAVETYP code (0 non-trafficway, 1 concrete, 2 asphalt, 3 brick, 4 gravel/stone, 5 dirt, 7 other, 8 not reported, 9 unknown):\n", t6b.to_string())
# list the individual unpaved-flagged AR-3/Sebastian crashes for audit
lst = AR6[AR6.unpaved_type_any | AR6.gravel_cond_any][["FARSYEAR", "County", "ST_CASE", "FATALS", "ROUTE", "RD_OWNER", "TWAY_ID",
                                                      "unpaved_type_any", "gravel_cond_any", "curve_any"]]
lst.to_csv(f"{OUT}/t6_unpaved_flagged_crashes_ar3_sebastian.csv", index=False)
print("\nIndividual flagged crashes (AR-3 + Sebastian):\n", lst.to_string(index=False))

# ----------------------------------------------------------------------------- crash-level audit file
keep = ["FARSYEAR", "County", "ST_CASE", "FATALS", "ROUTE", "RD_OWNER", "RUR_URB", "TWAY_ID", "curve_any", "align_known",
        "veh1_valign", "single_veh", "ror_A", "rollover_any", "night", "wet_any", "speed_any", "unpaved_type_any", "gravel_cond_any"]
AR6[keep].sort_values(["County", "FARSYEAR", "ST_CASE"]).to_csv(f"{OUT}/crash_level_ar3_sebastian.csv", index=False)

# vehicle-level coding quality in AR-3: how often VALIGN is missing
vv = Vk3.VALIGN.map({0: "0 Non-trafficway/driveway", 1: "1 Straight", 2: "2 Curve Right", 3: "3 Curve Left",
                     4: "4 Curve Unknown dir", 8: "8 Not reported", 9: "9 Reported unknown"}).value_counts()
print("\nAR-3 vehicle records by VALIGN:\n", vv.to_string())
vv.to_csv(f"{OUT}/t2_valign_distribution_ar3_vehicles.csv")
print("\nDONE. Files in", OUT)
for f in sorted(glob.glob(f"{OUT}/*.csv")) + [f"{OUT}/compute.py"]:
    print(f)
