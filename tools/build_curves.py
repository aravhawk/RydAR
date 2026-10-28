#!/usr/bin/env python3
"""
RydAR curve-screening prototype: Benton (FIPS 05007) + Washington (FIPS 05143) counties, Arkansas.

Rerun:  python3 tools/build_curves.py                         (uses cached downloads when present)
        python3 tools/build_curves.py --refetch                (re-download everything)

Inputs (all downloaded by this script):
  * Arkansas GIS Office ROADS_ACF centerlines, MapServer layer 18 (paginated, resultOffset)
  * Census TIGERweb county polygons (only to clip OSM to county lines)
  * Geofabrik arkansas-latest.osm.pbf (OSM highway ways, read with GDAL OSM driver through pyogrio)
Outputs in /tmp/rydar_curves/: curves.geojson, SUMMARY.md, results.json, plus caches.
"""
import json, math, os, re, sys, time, io
import concurrent.futures as cf
import numpy as np
import requests
import geopandas as gpd
import pandas as pd
import shapely
from shapely.geometry import LineString, MultiLineString, Point
from shapely.ops import linemerge
from pyproj import Transformer

OUT = "/tmp/rydar_curves"
os.makedirs(OUT, exist_ok=True)
T0 = time.time()
TIMES = {}
REFETCH = "--refetch" in sys.argv
FETCH_ONLY = "--fetch-only" in sys.argv

LAYER = "https://gis.arkansas.gov/arcgis/rest/services/FEATURESERVICES/Transportation/MapServer/18"
TIGER = "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/State_County/MapServer/11"
PBF_URL = "https://download.geofabrik.de/north-america/us/arkansas-latest.osm.pbf"
PBF = f"{OUT}/arkansas-latest.osm.pbf"
FIPS = {"007": "Benton", "143": "Washington"}   # 3-digit county FIPS as stored in cn_r_fips / cn_l_fips
WHERE = "cn_r_fips IN ('007','143') OR cn_l_fips IN ('007','143')"
CRS = "EPSG:26915"
FT = 0.3048
MI = 1609.344

# ---- curve-detection parameters ----
DS = 5.0            # densification step (m)
WIN = 40.0          # arc length between outer points of the Menger triple (m)  -> +-20 m
SMOOTH = 3          # moving-average width on signed curvature (samples) -> 15 m
MIN_LEN = 30.0      # minimum stretch length below threshold (m)
THR_FT = [600, 300, 150]
E_SUPER = 0.02
F_PAVED_WET = 0.15
F_UNPAVED = [0.10, 0.08]


def tick(name):
    TIMES[name] = round(time.time() - T0, 1)
    print(f"[{TIMES[name]:7.1f}s] {name}", flush=True)


# ===================================================================== fetch
def fetch_json(url, params, tries=6):
    for a in range(tries):
        try:
            r = requests.get(url, params=params, timeout=120)
            r.raise_for_status()
            j = r.json()
            if "error" in j:
                raise RuntimeError(j["error"])
            return j
        except Exception as e:  # noqa
            FAILS.append(f"{url.split('/')[-1]} {params.get('resultOffset')} try{a}: {e}")
            time.sleep(1.5 * (a + 1))
    raise RuntimeError("fetch failed: " + str(params))


FAILS = []


def esri_geom(g):
    if g is None:
        return None
    if "curvePaths" in g:
        raise RuntimeError("true curves present")
    parts = [p for p in g["paths"] if len(p) >= 2]
    if not parts:
        return None
    return LineString(parts[0]) if len(parts) == 1 else MultiLineString(parts)


def fetch_centerlines():
    cache = f"{OUT}/centerlines.gpkg"
    meta_cache = f"{OUT}/centerlines_fetch_meta.json"
    if os.path.exists(cache) and not REFETCH:
        return gpd.read_file(cache), json.load(open(meta_cache))
    q = LAYER + "/query"
    info = fetch_json(LAYER, {"f": "json"})
    maxrec = info["maxRecordCount"]
    fields = [f["name"] for f in info["fields"]]
    total = fetch_json(q, {"where": WHERE, "returnCountOnly": "true", "f": "json"})["count"]
    cnts = {}
    for fp, nm in FIPS.items():
        cnts[nm] = {
            "cn_r_fips": fetch_json(q, {"where": f"cn_r_fips='{fp}'", "returnCountOnly": "true", "f": "json"})["count"],
            "cn_l_fips": fetch_json(q, {"where": f"cn_l_fips='{fp}'", "returnCountOnly": "true", "f": "json"})["count"],
        }
    print("server count (union where):", total, "maxRecordCount:", maxrec)
    offsets = list(range(0, total, maxrec))
    npages = len(offsets)

    def page(off):
        j = fetch_json(q, {"where": WHERE, "outFields": "*", "returnGeometry": "true", "outSR": 26915,
                           "orderByFields": "objectid", "resultOffset": off, "resultRecordCount": maxrec, "f": "json"})
        return off, j["features"], j.get("exceededTransferLimit")

    rows, geoms, got = [], [], {}
    with cf.ThreadPoolExecutor(6) as ex:
        for off, feats, exc in ex.map(page, offsets):
            got[off] = len(feats)
            for f in feats:
                rows.append(f["attributes"])
                geoms.append(esri_geom(f.get("geometry")))
    gdf = gpd.GeoDataFrame(rows, geometry=geoms, crs=CRS)
    n_raw = len(gdf)
    gdf = gdf.drop_duplicates("objectid")
    meta = {"service_info": {"maxRecordCount": maxrec, "fields": [(f["name"], f["type"], f.get("length")) for f in info["fields"]],
                             "currentVersion": info.get("currentVersion")},
            "server_count_union": total, "pages": npages, "rows_fetched": n_raw, "rows_unique_objectid": len(gdf),
            "null_geometry": int(gdf.geometry.isna().sum()), "fips_counts": cnts, "fetch_failures": FAILS[:],
            "page_sizes_min_max": [min(got.values()), max(got.values())]}
    gdf = gdf[~gdf.geometry.isna()].copy()
    # global id braces etc are fine; shorten column names that gpkg dislikes
    gdf = gdf.rename(columns={"st_length(shape)": "st_length_shape"})
    gdf.to_file(cache, driver="GPKG")
    json.dump(meta, open(meta_cache, "w"), indent=1)
    return gdf, meta


def fetch_counties():
    cache = f"{OUT}/counties.geojson"
    if not os.path.exists(cache) or REFETCH:
        r = requests.get(TIGER + "/query", params={"where": "STATE='05' AND COUNTY IN ('007','143')",
                                                   "outFields": "GEOID,NAME,COUNTY", "outSR": 4326, "f": "geojson"}, timeout=60)
        r.raise_for_status()
        open(cache, "w").write(r.text)
    return gpd.read_file(cache)


def fetch_pbf():
    if os.path.exists(PBF) and not REFETCH:
        return
    with requests.get(PBF_URL, stream=True, timeout=600) as r:
        r.raise_for_status()
        with open(PBF, "wb") as fh:
            for ch in r.iter_content(1 << 20):
                fh.write(ch)


# ============================================================ curve detection
def wrap(a):
    return (a + np.pi) % (2 * np.pi) - np.pi


def menger_kappa(P, k):
    """signed curvature at samples k..n-1-k from triple (i-k, i, i+k)"""
    a, b, c = P[:-2 * k], P[k:-k], P[2 * k:]
    ab, bc, ac = b - a, c - b, c - a
    cross = ab[:, 0] * ac[:, 1] - ab[:, 1] * ac[:, 0]
    den = np.hypot(*ab.T) * np.hypot(*bc.T) * np.hypot(*ac.T)
    return 2 * cross / np.maximum(den, 1e-9)


def smooth(x, w):
    w = min(w, len(x))
    if w % 2 == 0:
        w -= 1
    if w <= 1 or len(x) < 2:
        return x
    ker = np.ones(w) / w
    num = np.convolve(x, ker, mode="same")
    nrm = np.convolve(np.ones_like(x), ker, mode="same")
    return num / nrm


def resample(xy, ds=DS):
    seg = np.hypot(*np.diff(xy, axis=0).T)
    cum = np.r_[0, np.cumsum(seg)]
    L = cum[-1]
    if L < 1:
        return None, None, cum
    n = max(int(round(L / ds)), 1) + 1
    s = np.linspace(0, L, n)
    return np.c_[np.interp(s, cum, xy[:, 0]), np.interp(s, cum, xy[:, 1])], s, cum


def chain_kappa(xy, win=WIN, smooth_w=SMOOTH, ds=DS):
    """returns dict with resampled points P, arc s, signed smoothed curvature kap (nan where undefined), heading step dh"""
    closed = len(xy) > 3 and np.hypot(*(xy[0] - xy[-1])) < 0.5
    P, s, cum = resample(xy, ds)
    if P is None:
        return None
    n = len(P)
    d = s[1] - s[0]
    k = max(1, int(round(win / 2 / d)))
    if closed and n > 3:
        Pc = P[:-1]
        m = len(Pc)
        pad = np.r_[np.arange(m - k, m), np.arange(m), np.arange(0, k)]
        Pp = Pc[pad % m]
        kap = menger_kappa(Pp, k)            # len m
        kap = smooth(kap, smooth_w)
        kap = np.r_[kap, kap[:1]]            # back to n samples
        valid = np.ones(n, bool)
    else:
        if n < 2 * k + 1:
            return None
        kap_in = smooth(menger_kappa(P, k), smooth_w)
        kap = np.full(n, np.nan)
        kap[k:n - k] = kap_in
        valid = ~np.isnan(kap)
    h = np.arctan2(*np.diff(P, axis=0).T[::-1])
    dh = wrap(np.diff(h))                    # turning at samples 1..n-2 (index m-1)
    return dict(P=P, s=s, ds=d, k=k, kap=kap, valid=valid, dh=dh, closed=closed, cum=cum, n=n)


def stretches(ck, thr_m, min_len=MIN_LEN):
    kap, valid = ck["kap"], ck["valid"]
    n, d = ck["n"], ck["ds"]
    mask = valid & (np.abs(np.nan_to_num(kap)) > 1.0 / thr_m)
    sgn = np.sign(np.nan_to_num(kap))
    out = []
    i = 0
    while i < n:
        if not mask[i]:
            i += 1
            continue
        j = i
        while j + 1 < n and mask[j + 1] and sgn[j + 1] == sgn[i]:
            j += 1
        if (j - i) * d >= min_len - 1e-9:
            out.append((i, j))
        i = j + 1
    return out


def stretch_stats(ck, i, j):
    kap = np.abs(ck["kap"][i:j + 1])
    R = 1.0 / np.maximum(kap, 1e-9)
    im = int(np.argmin(R))
    dh = ck["dh"]
    lo, hi = max(i - 1, 0), min(j, len(dh))
    defl = abs(math.degrees(dh[lo:hi].sum())) if hi > lo else 0.0
    return dict(rmin=float(R.min()), rmed=float(np.median(R)), imin=i + im, defl=defl,
                length=float((j - i) * ck["ds"]))


# ============================================================== speeds
def v_mph(R_ft, e, f):
    return np.sqrt(15.0 * np.asarray(R_ft, float) * (e + f))


# ================================================================ helpers
ALL_THR_FT = [150, 300, 600, 800, 1700]   # 150/300/600 are the requested tiers; 800/1700 only used for the speed-bucket question
GEO_THR = 600


def fmt(x, nd=1):
    if x is None or (isinstance(x, float) and (math.isnan(x))):
        return "n/a"
    if isinstance(x, (int, np.integer)):
        return f"{x:,}"
    return f"{x:,.{nd}f}"


def md_table(df, index=True, nd=1):
    d = df.reset_index() if index else df
    cols = [str(c) for c in d.columns]
    lines = ["| " + " | ".join(cols) + " |", "|" + "|".join(["---"] * len(cols)) + "|"]
    for _, r in d.iterrows():
        lines.append("| " + " | ".join(fmt(v, nd) if not isinstance(v, str) else v for v in r.values) + " |")
    return "\n".join(lines)


def build_chains(g, merge=True, decimate=False):
    """g: GeoDataFrame in UTM with county_name, rd_class, surface, rd_design, name.  returns list of dict chains"""
    chains = []
    keys = ["county_name", "rd_class", "surface", "rd_design", "name"]
    if merge:
        for key, sub in g.groupby(keys, dropna=False, sort=False):
            geoms = []
            for geom in sub.geometry.values:
                geoms.extend(geom.geoms if geom.geom_type == "MultiLineString" else [geom])
            ml = shapely.line_merge(shapely.multilinestrings(geoms)) if len(geoms) > 1 else geoms[0]
            parts = list(ml.geoms) if ml.geom_type == "MultiLineString" else [ml]
            # number of source segments per merged part is approximated by vertex count only; keep nseg for the group
            for p in parts:
                chains.append(dict(key=key, line=p, nseg_group=len(sub)))
    else:
        for geom, row in zip(g.geometry.values, g[keys].itertuples(index=False)):
            parts = list(geom.geoms) if geom.geom_type == "MultiLineString" else [geom]
            for p in parts:
                chains.append(dict(key=tuple(row), line=p, nseg_group=1))
    for c in chains:
        xy = np.asarray(c["line"].coords)[:, :2]
        if decimate and len(xy) > 3:
            idx = np.unique(np.r_[np.arange(0, len(xy), 2), len(xy) - 1])
            xy = xy[idx]
        c["xy"] = xy
    return chains


def detect(chains, win=WIN, thr_ft=ALL_THR_FT, keep_geom_thr=None, to_ll=None):
    """returns dict thr_ft -> list of row dicts (one per detected curve stretch)"""
    out = {t: [] for t in thr_ft}
    for ci, c in enumerate(chains):
        xy = c["xy"]
        if len(xy) < 2:
            continue
        ck = chain_kappa(xy, win=win)
        if ck is None:
            continue
        for t in thr_ft:
            for (i, j) in stretches(ck, t * FT):
                st = stretch_stats(ck, i, j)
                row = dict(chain=ci, i=i, j=j, rmin_m=st["rmin"], rmed_m=st["rmed"], defl=st["defl"], length=st["length"],
                           county=c["key"][0], rd_class=c["key"][1], surface=c["key"][2], rd_design=c["key"][3], name=c["key"][4],
                           closed=bool(ck["closed"]), side="L" if ck["kap"][i] > 0 else "R")
                if keep_geom_thr is not None and t == keep_geom_thr:
                    s_lo, s_hi = ck["s"][i] - win / 2, ck["s"][j] + win / 2
                    nv = int(((ck["cum"] >= s_lo) & (ck["cum"] <= s_hi)).sum())
                    rng = s_hi - s_lo
                    row["n_vert_win"] = nv
                    row["vert_spacing_m"] = rng / max(nv - 1, 1) if nv >= 2 else rng
                    row["P"] = ck["P"][i:j + 1].copy()
                    row["pmin"] = ck["P"][st["imin"]].copy()
                    row["s_i"], row["s_j"] = float(ck["s"][i]), float(ck["s"][j])
                out[t].append(row)
    return out


def overlap_flag(rows_hi, rows_lo):
    """for each curve in rows_hi (600ft) flag whether a stretch of rows_lo (same chain) overlaps its sample range"""
    by = {}
    for r in rows_lo:
        by.setdefault(r["chain"], []).append((r["i"], r["j"]))
    fl = []
    for r in rows_hi:
        fl.append(any(not (b < r["i"] or a > r["j"]) for a, b in by.get(r["chain"], [])))
    return fl


# ===================================================== synthetic validation
def make_arc(R_m, sweep_deg=90.0, tang=80.0, vsp=10.0):
    th = math.radians(sweep_deg)
    La = R_m * th
    tot = tang + La + tang
    s = np.linspace(0, tot, int(round(tot / vsp)) + 1)
    x = np.zeros_like(s); y = np.zeros_like(s)
    for n, sv in enumerate(s):
        if sv <= tang:
            x[n], y[n] = sv, 0
        elif sv <= tang + La:
            a = (sv - tang) / R_m
            x[n] = tang + R_m * math.sin(a); y[n] = R_m * (1 - math.cos(a))
        else:
            d = sv - tang - La
            x[n] = tang + R_m * math.sin(th) + d * math.cos(th)
            y[n] = R_m * (1 - math.cos(th)) + d * math.sin(th)
    return np.c_[x, y], (tang, tang + La), s


def synthetic_test(rng, ntrial=200):
    rows = []
    for Rft in (100, 200, 500):
        Rm = Rft * FT
        for vsp in (10.0, 25.0):
            for sig in (0.0, 1.0, 3.0):
                xy0, (a0, a1), s0 = make_arc(Rm, vsp=vsp)
                est_mid, est_min, det = [], [], 0
                for _ in range(1 if sig == 0 else ntrial):
                    xy = xy0 + rng.normal(0, sig, xy0.shape)
                    ck = chain_kappa(xy)
                    s = ck["s"]
                    # arc-interior samples (>=10 m inside arc ends) using the noise-free arclength approx (noise is small vs length)
                    inside = (s >= a0 + 10) & (s <= a1 - 10) & ck["valid"]
                    if inside.sum() >= 3:
                        Rs = 1.0 / np.maximum(np.abs(ck["kap"][inside]), 1e-9)
                        est_mid.append(np.median(Rs))
                    # pipeline estimate: min radius in any <600ft stretch overlapping the arc zone
                    cand = []
                    for (i, j) in stretches(ck, 600 * FT):
                        if s[j] >= a0 and s[i] <= a1:
                            cand.append(stretch_stats(ck, i, j)["rmin"])
                    if cand:
                        det += 1
                        est_min.append(min(cand))
                nt = 1 if sig == 0 else ntrial
                em = np.array(est_mid) / FT / Rft
                en = np.array(est_min) / FT / Rft if est_min else np.array([np.nan])
                rows.append(dict(R_true_ft=Rft, vertex_spacing_m=vsp, noise_sigma_m=sig,
                                 median_arc_R_est_over_true=float(np.median(em)),
                                 p10_p90_arc_ratio=f"{np.percentile(em, 10):.2f}-{np.percentile(em, 90):.2f}",
                                 median_abs_err_pct=float(np.median(np.abs(em - 1)) * 100),
                                 detect_rate_lt600ft=det / nt,
                                 pipeline_rmin_over_true_median=float(np.nanmedian(en)),
                                 pipeline_p10_p90=f"{np.nanpercentile(en, 10):.2f}-{np.nanpercentile(en, 90):.2f}"))
    fp = []
    for vsp in (10.0, 25.0):
        for sig in (0.0, 1.0, 3.0):
            n600 = n300 = 0
            km = 0
            for _ in range(1 if sig == 0 else 50):
                x = np.arange(0, 2000.0 + 1e-6, vsp)
                xy = np.c_[x, np.zeros_like(x)] + rng.normal(0, sig, (len(x), 2))
                ck = chain_kappa(xy)
                n600 += len(stretches(ck, 600 * FT)); n300 += len(stretches(ck, 300 * FT)); km += 2.0
            fp.append(dict(vertex_spacing_m=vsp, noise_sigma_m=sig, straight_km_tested=km,
                           false_curves_lt600ft_per_km=n600 / km, false_curves_lt300ft_per_km=n300 / km))
    return pd.DataFrame(rows), pd.DataFrame(fp)


# ===================================================================== OSM
PAVED = {"asphalt", "concrete", "paved", "concrete:plates", "concrete:lanes", "paving_stones", "sett", "chipseal", "bricks", "brick", "metal", "cobblestone"}
UNPAVED = {"gravel", "dirt", "unpaved", "ground", "compacted", "fine_gravel", "earth", "sand", "grass", "mud", "pebblestone", "dirt/sand", "rock", "woodchips", "clay", "salt"}
ROADS = {"motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "living_street", "track",
         "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link"}
TAGRE = re.compile(r'"((?:[^"\\]|\\.)*)"=>"((?:[^"\\]|\\.)*)"')


def parse_tags(s):
    return dict(TAGRE.findall(s)) if isinstance(s, str) else {}


def load_osm(counties):
    import pyogrio
    cache = f"{OUT}/osm_highways_counties.gpkg"
    if os.path.exists(cache) and not REFETCH:
        return gpd.read_file(cache)
    o = pyogrio.read_dataframe(PBF, layer="lines", where="highway IS NOT NULL", bbox=tuple(counties.total_bounds))
    n_bbox = len(o)
    tags = o["other_tags"].map(parse_tags)
    for k in ["maxspeed", "surface", "smoothness", "lanes", "curve", "tracktype", "oneway", "ref", "access"]:
        o[k] = tags.map(lambda d, k=k: d.get(k))
    o = o.drop(columns=["other_tags", "waterway", "aerialway", "barrier", "man_made", "railway"])
    cl = gpd.clip(o, counties[["geometry"]].to_crs(4326))
    cl = cl.explode(index_parts=False)
    cl = cl[cl.geom_type == "LineString"].copy()
    cl["osm_n_bbox"] = n_bbox
    cl.to_file(cache, driver="GPKG")
    return cl


def sample_points(lines, step=50.0):
    L = lines.length.values
    n = np.maximum((L // step).astype(int), 1)
    idx = np.repeat(np.arange(len(lines)), n)
    k = np.concatenate([np.arange(m) for m in n])
    d = (k + 0.5) / n[idx] * L[idx]
    pts = shapely.line_interpolate_point(lines.geometry.values[idx], d)
    return idx, gpd.GeoSeries(pts, crs=lines.crs), L[idx] / n[idx]


def surf_class(v):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return "no surface tag"
    return "paved" if v in PAVED else ("unpaved" if v in UNPAVED else "other value")


def osm_analysis(g, counties, R):
    osm = load_osm(counties)
    osm_u = osm.to_crs(CRS)
    osm_u["len_m"] = osm_u.length
    od = {}
    od["bbox_ways_read"] = int(osm["osm_n_bbox"].iloc[0])
    od["ways_clipped_to_two_counties"] = len(osm_u)
    hw = osm_u.groupby("highway").agg(ways=("osm_id", "size"), km=("len_m", lambda x: x.sum() / 1000)).sort_values("ways", ascending=False)
    od["highway_counts"] = hw
    roads = osm_u[osm_u.highway.isin(ROADS)].copy()
    od["road_ways"] = len(roads)
    od["road_km"] = roads.len_m.sum() / 1000
    roads["has_maxspeed"] = roads.maxspeed.notna()
    roads["has_surface"] = roads.surface.notna()
    roads["surf_osm"] = roads.surface.map(surf_class)
    # tag presence by highway class
    t = roads.groupby("highway").agg(ways=("osm_id", "size"), km=("len_m", lambda x: x.sum() / 1000),
                                     maxspeed_pct=("has_maxspeed", lambda x: 100 * x.mean()),
                                     surface_pct=("has_surface", lambda x: 100 * x.mean()),
                                     smoothness_n=("smoothness", lambda x: int(x.notna().sum())),
                                     lanes_n=("lanes", lambda x: int(x.notna().sum())),
                                     curve_tag_n=("curve", lambda x: int(x.notna().sum())))
    od["by_highway"] = t.sort_values("ways", ascending=False)
    od["tag_totals"] = {k: int(roads[k].notna().sum()) for k in ["maxspeed", "surface", "smoothness", "lanes", "curve", "tracktype"]}
    od["curve_tag_values"] = roads["curve"].dropna().value_counts().to_dict()
    od["surface_values"] = roads["surface"].dropna().value_counts().head(15).to_dict()
    od["maxspeed_values"] = roads["maxspeed"].dropna().value_counts().head(12).to_dict()

    # length-weighted match to ACF: 50 m sample points on OSM road ways -> nearest ACF centerline within 15 m
    idx, pts, w = sample_points(roads, 50.0)
    sp = gpd.GeoDataFrame({"way": idx, "w": w}, geometry=pts.values, crs=CRS)
    acf = g[["rd_class", "surface", "geometry"]].reset_index(drop=True)
    m = gpd.sjoin_nearest(sp, acf, how="left", max_distance=15.0, distance_col="dist")
    m = m[~m.index.duplicated(keep="first")]
    for c in ["has_maxspeed", "has_surface", "surf_osm", "highway"]:
        m[c] = roads[c].values[m["way"].values]
    m["matched"] = m["rd_class"].notna()
    od["sample_points"] = len(m)
    od["sample_matched_pct"] = 100 * m["matched"].mean()
    m["grp"] = np.where(~m.matched, "unmatched to ACF", np.where(m.rd_class == "County", "ACF County", "ACF other class"))
    rows = []
    for (grp, surf), sub in m[m.matched].groupby(["grp", "surface"]):
        tot = sub.w.sum()
        rows.append(dict(ACF_group=grp, ACF_surface=surf, osm_km=tot / 1000,
                         pct_with_maxspeed=100 * sub.w[sub.has_maxspeed].sum() / tot,
                         pct_with_surface_tag=100 * sub.w[sub.has_surface].sum() / tot,
                         osm_surface_agrees_pct_of_tagged=100 * sub.w[((sub.surf_osm == "paved") & (sub.surface == "Paved")) | ((sub.surf_osm == "unpaved") & (sub.surface == "Unpaved"))].sum() / max(sub.w[sub.has_surface].sum(), 1)))
    od["acf_matched"] = pd.DataFrame(rows).sort_values(["ACF_group", "ACF_surface"])
    # OSM ways only, county proxy (non-state/non-motorway)
    prox = roads[roads.highway.isin(["tertiary", "unclassified", "track", "residential"])]
    od["proxy"] = dict(ways=len(prox), maxspeed_pct=100 * prox.has_maxspeed.mean(), surface_pct=100 * prox.has_surface.mean(),
                       unclassified_track_ways=int(prox.highway.isin(["unclassified", "track"]).sum()),
                       unclass_track_maxspeed_pct=100 * prox[prox.highway.isin(["unclassified", "track"])].has_maxspeed.mean(),
                       unclass_track_surface_pct=100 * prox[prox.highway.isin(["unclassified", "track"])].has_surface.mean())
    # maxspeed values on ACF County-matched points
    cm = m[(m.grp == "ACF County")]
    od["county_maxspeed_dist"] = pd.Series(roads["maxspeed"].values[cm.loc[cm.has_maxspeed, "way"].values]).value_counts().head(10).to_dict() if cm.has_maxspeed.any() else {}
    return od, roads


# ======================================================================= main
def main():
    R = {}
    fetch_pbf()
    tick("pbf downloaded/cached")
    gdf, meta = fetch_centerlines()
    counties = fetch_counties()
    tick("centerlines fetched/cached")
    R["fetch"] = meta
    if FETCH_ONLY:
        return
    rng = np.random.default_rng(42)

    # ---------------------------------------------------------------- prep
    g = gdf.copy()
    fr = g["cn_r_fips"].where(g["cn_r_fips"].isin(FIPS), None)
    fl = g["cn_l_fips"].where(g["cn_l_fips"].isin(FIPS), None)
    g["fips"] = fr.fillna(fl)
    g["fips"] = g["fips"].fillna(g["meta_id"].str[-3:].where(g["meta_id"].str[-3:].isin(FIPS)))
    R["n_assigned_none"] = int(g["fips"].isna().sum())
    g = g[g["fips"].notna()].copy()
    g["county_name"] = g["fips"].map(FIPS)
    R["boundary_lr_mismatch"] = int(((g.cn_r_fips != g.cn_l_fips) & g.cn_r_fips.notna() & g.cn_l_fips.notna()).sum())
    R["fips_vs_meta_id_disagree"] = int((g["fips"] != g["meta_id"].str[-3:]).sum())
    g["surface"] = g["rd_surftyp"].fillna("Unknown")
    g["name"] = g["pstr_fulnam"].fillna("").str.strip()
    g["county_road"] = g["rd_class"].eq("County")
    g["len_m"] = g.geometry.length
    g["len_mi"] = g["len_m"] / MI
    R["n_records"] = len(g)
    R["fields"] = meta["service_info"]["fields"]
    R["date_ed"] = g["date_ed"].value_counts().sort_index().to_dict()
    R["date_ed_by_county"] = g.groupby("county_name")["date_ed"].agg(["min", "max"]).reset_index()
    R["len_ratio_utm_over_st_length"] = float((g["len_m"].sum()) / g["st_length_shape"].sum())
    tick("prep")

    # counts / miles
    R["cnt_class_surf"] = g.pivot_table(index=["county_name", "rd_class"], columns="surface", values="objectid", aggfunc="count", fill_value=0)
    R["mi_class_surf"] = g.pivot_table(index=["county_name", "rd_class"], columns="surface", values="len_mi", aggfunc="sum", fill_value=0)
    R["mi_surf"] = g.pivot_table(index="county_name", columns="surface", values="len_mi", aggfunc="sum", fill_value=0)
    R["mi_county_roads"] = g[g.county_road].pivot_table(index="county_name", columns="surface", values="len_mi", aggfunc="sum", fill_value=0)
    R["cnt_county_roads"] = g[g.county_road].pivot_table(index="county_name", columns="surface", values="objectid", aggfunc="count", fill_value=0)
    R["design_counts"] = g["rd_design"].value_counts().to_dict()
    R["surface_counts"] = g["surface"].value_counts().to_dict()

    # vertex spacing
    co, ix = shapely.get_coordinates(g.geometry.values, return_index=True)
    d = np.hypot(*np.diff(co, axis=0).T)
    same = ix[1:] == ix[:-1]
    d, ixd = d[same], ix[1:][same]
    vs = pd.DataFrame({"d": d, "surface": g["surface"].values[ixd], "cr": g["county_road"].values[ixd], "cls": g["rd_class"].values[ixd]})
    R["vsp"] = dict(n_gaps=len(d), median=float(np.median(d)), p10=float(np.percentile(d, 10)), p90=float(np.percentile(d, 90)),
                    frac_gt20=float((d > 20).mean()), frac_gt50=float((d > 50).mean()),
                    mean_vertices_per_segment=float(np.bincount(ix).mean()))
    R["vsp_by"] = vs.groupby(["cls", "surface"]).d.agg(median="median", p90=lambda x: np.percentile(x, 90), n="size").reset_index()
    tick("vertex spacing")

    # ------------------------------------------------------------ detection
    chains = build_chains(g, merge=True)
    R["n_chains"] = len(chains)
    tick(f"chains built ({len(chains)} chains from {len(g)} segments)")
    t0 = time.time()
    res = detect(chains, WIN, ALL_THR_FT, keep_geom_thr=GEO_THR)
    R["time_detect_main_s"] = time.time() - t0
    tick("detection main")
    dfs = {}
    for t in ALL_THR_FT:
        df = pd.DataFrame([{k: v for k, v in r.items() if k not in ("P", "pmin")} for r in res[t]])
        df["radius_ft"] = df["rmin_m"] / FT
        df["class_grp"] = np.where(df["rd_class"] == "County", "County", "Other")
        dfs[t] = df
    R["n_curves"] = {t: len(dfs[t]) for t in ALL_THR_FT}

    # sensitivity runs (counts only)
    sens = []
    def cnt(label, resx):
        row = {"run": label}
        for t in (150, 300, 600):
            row[f"<{t}ft"] = len(resx[t])
            row[f"<{t}ft county-class"] = sum(1 for r in resx[t] if r["rd_class"] == "County")
        sens.append(row)
    cnt("main: win 40 m, merged chains", res)
    for w in (30.0, 60.0):
        cnt(f"window {int(w)} m", detect(chains, w, (150, 300, 600)))
    cnt("no chain merge (each segment alone)", detect(build_chains(g, merge=False), WIN, (150, 300, 600)))
    cnt("vertices decimated 2x (every other vertex)", detect(build_chains(g, merge=True, decimate=True), WIN, (150, 300, 600)))
    R["sens"] = pd.DataFrame(sens)
    tick("sensitivity runs")

    # per-curve metadata for the 600 ft set (geojson)
    rows600 = res[GEO_THR]
    d6 = dfs[GEO_THR].copy()
    d6["has_lt300"] = overlap_flag(rows600, res[300])
    d6["has_lt150"] = overlap_flag(rows600, res[150])
    R["ah_nonnull"] = {c: int(g[c].notna().sum()) for c in g.columns if c.startswith("ah_")}
    d6["n_vert_win"] = [r["n_vert_win"] for r in rows600]
    d6["vert_spacing_m"] = [r["vert_spacing_m"] for r in rows600]
    tr = Transformer.from_crs(CRS, 4326, always_xy=True)
    pm = np.array([r["pmin"] for r in rows600])
    lon, lat = tr.transform(pm[:, 0], pm[:, 1])
    d6["lat"], d6["lon"] = lat, lon
    d6["pmin_x"], d6["pmin_y"] = pm[:, 0], pm[:, 1]
    d6["screening_mph_paved_wet"] = v_mph(d6["radius_ft"], E_SUPER, F_PAVED_WET)
    d6["screening_mph_unpaved"] = v_mph(d6["radius_ft"], E_SUPER, F_UNPAVED[0])
    d6["screening_mph_unpaved_f008"] = v_mph(d6["radius_ft"], E_SUPER, F_UNPAVED[1])
    # data-quality flags (heuristic): likely artefacts / low-confidence geometry
    def qflags(r):
        fl = []
        if r.closed: fl.append("closed_loop")
        if r.rd_design not in ("Single Carriageway", "Dual Carriageway", "Frontage Road"): fl.append("ramp_circle_connector")
        if r.radius_ft < 50: fl.append("lt50ft_corner_or_hairpin")
        if r.vert_spacing_m > 25: fl.append("sparse_vertices_gt25m")
        return ";".join(fl)
    dfs[GEO_THR] = d6
    d6["quality_flags"] = d6.apply(qflags, axis=1)
    d6["clean"] = d6.quality_flags.eq("")

    # --------------------------------------------------------- curve stats
    def sub_label(df):
        return {"all curves": df, "County-class roads": df[df.class_grp == "County"], "unpaved (all classes)": df[df.surface == "Unpaved"],
                "County-class unpaved": df[(df.class_grp == "County") & (df.surface == "Unpaved")],
                "County-class paved": df[(df.class_grp == "County") & (df.surface == "Paved")]}
    cc, dist = [], []
    for t in (600, 300, 150):
        df = dfs[t]
        piv = df.pivot_table(index=["county", "class_grp", "surface"], values="chain", aggfunc="count", fill_value=0).rename(columns={"chain": f"R<{t} ft"})
        cc.append(piv)
        for lab, s in sub_label(df).items():
            if len(s):
                dist.append(dict(threshold_ft=t, subset=lab, n=len(s), median_ft=s.radius_ft.median(), p10_ft=s.radius_ft.quantile(0.1), min_ft=s.radius_ft.min(),
                                 median_len_m=s.length.median(), median_defl_deg=s.defl.median()))
            else:
                dist.append(dict(threshold_ft=t, subset=lab, n=0, median_ft=np.nan, p10_ft=np.nan, min_ft=np.nan, median_len_m=np.nan, median_defl_deg=np.nan))
    R["curve_counts"] = pd.concat(cc, axis=1).fillna(0).astype(int)
    R["curve_dist"] = pd.DataFrame(dist)
    cl6 = d6[d6.clean]
    R["clean_counts_600"] = cl6.pivot_table(index=["county", "class_grp", "surface"], values="chain", aggfunc="count", fill_value=0).rename(columns={"chain": "clean R<600ft"}).join(
        d6[d6.radius_ft < 300].pipe(lambda x: x[x.clean]).pivot_table(index=["county", "class_grp", "surface"], values="chain", aggfunc="count", fill_value=0).rename(columns={"chain": "clean R<300ft (min radius)"}), how="outer").fillna(0).astype(int)
    R["flag_counts_600"] = d6.quality_flags.replace("", "(none)").str.split(";").explode().value_counts().to_dict()
    R["clean_n_600"] = int(d6.clean.sum())
    R["curve_by_class_600"] = dfs[600].pivot_table(index=["county", "rd_class"], columns="surface", values="chain", aggfunc="count", fill_value=0)
    miles = g.groupby(["county_name", "county_road", "surface"]).len_mi.sum()
    dens = []
    for t in (600, 300, 150):
        d_ = dfs[t].groupby(["county", dfs[t].class_grp.eq("County").rename("county_road"), "surface"]).size()
        for k, v in d_.items():
            dens.append(dict(threshold_ft=t, county=k[0], county_class="County" if k[1] else "Other", surface=k[2], curves=v, road_miles=miles.get((k[0], k[1], k[2]), np.nan),
                             curves_per_100mi=100 * v / miles.get((k[0], k[1], k[2]), np.nan)))
    R["density"] = pd.DataFrame(dens)
    R["dual_curves_600"] = int((dfs[600].rd_design != "Single Carriageway").sum())
    R["design_curves_600"] = dfs[600].rd_design.value_counts().to_dict()
    R["closed_curves_600"] = int(dfs[600].closed.sum())
    # vertex-spacing effect on curve density (by chain median spacing)
    cs = []
    for ci, c in enumerate(chains):
        xy = c["xy"]
        if len(xy) < 2:
            continue
        dd = np.hypot(*np.diff(xy, axis=0).T)
        cs.append((ci, np.median(dd), dd.sum()))
    cs = pd.DataFrame(cs, columns=["chain", "med_sp", "len"])
    cs["bin"] = pd.cut(cs.med_sp, [0, 10, 25, 50, 1e9], labels=["<=10 m", "10-25 m", "25-50 m", ">50 m"])
    cnt600 = dfs[600].groupby("chain").size()
    cs["n600"] = cs.chain.map(cnt600).fillna(0)
    R["vsp_effect"] = cs.groupby("bin", observed=True).apply(lambda s: pd.Series({"chains": len(s), "km": s.len.sum() / 1000, "curves_lt600ft": int(s.n600.sum()),
                                                                                  "curves_per_100km": 100 * s.n600.sum() / (s.len.sum() / 1000)})).reset_index()
    R["vsp_effect"] = R["vsp_effect"].astype({"chains": int, "curves_lt600ft": int})
    R["curve_vsp_median"] = float(dfs[600].vert_spacing_m.median())
    tick("stats")

    # -------------------------------------------------------------- speeds
    brk = []
    for lab, f in (("paved wet f=0.15", 0.15), ("unpaved f=0.10", 0.10), ("unpaved f=0.08", 0.08)):
        brk.append(dict(assumption=lab, **{f"R_ft_for_{v}mph": v * v / (15 * (E_SUPER + f)) for v in (25, 35, 45)}))
    R["speed_breaks"] = pd.DataFrame(brk)
    sp = []
    for t in ALL_THR_FT:
        df = dfs[t]
        for surf, f, lab in (("Paved", 0.15, "paved wet f=0.15"), ("Unpaved", 0.10, "unpaved f=0.10"), ("Unpaved", 0.08, "unpaved f=0.08")):
            s = df[df.surface == surf]
            v = v_mph(s.radius_ft, E_SUPER, f)
            for sub, mask in (("all classes", np.ones(len(s), bool)), ("County-class", (s.class_grp == "County").values)):
                vv = v[mask]
                sp.append({"R_thr_ft": t, "surface": surf, "assumption": lab, "subset": sub, "n_curves": int(mask.sum()),
                           "<25mph": int((vv < 25).sum()), "<35mph": int((vv < 35).sum()), "<45mph": int((vv < 45).sum()),
                           "median_mph": float(np.median(vv)) if len(vv) else np.nan})
    R["speed_counts"] = pd.DataFrame(sp)
    tick("speeds")

    # ---------------------------------------------------------------- OSM
    od, osm_roads = osm_analysis(g, counties, R)
    R["osm"] = od
    tick("osm analysis")

    # curve <-> OSM nearest way
    cp = gpd.GeoDataFrame({"cid": np.arange(len(d6))}, geometry=gpd.points_from_xy(d6.pmin_x, d6.pmin_y), crs=CRS)
    oi = osm_roads.reset_index(drop=True)[["osm_id", "highway", "maxspeed", "surface", "lanes", "geometry"]]
    mm = gpd.sjoin_nearest(cp, oi, how="left", max_distance=20.0, distance_col="d_osm")
    mm = mm[~mm.index.duplicated(keep="first")].sort_index()
    d6["osm_id"] = mm["osm_id"].values
    d6["osm_highway"] = mm["highway"].values
    d6["osm_maxspeed"] = mm["maxspeed"].values
    d6["osm_surface"] = mm["surface"].values
    R["curve_osm"] = {"n": len(d6), "matched_pct": 100 * d6.osm_id.notna().mean(),
                      "maxspeed_pct_of_all": 100 * d6.osm_maxspeed.notna().mean(),
                      "surface_pct_of_all": 100 * d6.osm_surface.notna().mean(),
                      "county_unpaved_maxspeed_pct": 100 * d6[(d6.class_grp == "County") & (d6.surface == "Unpaved")].osm_maxspeed.notna().mean(),
                      "county_paved_maxspeed_pct": 100 * d6[(d6.class_grp == "County") & (d6.surface == "Paved")].osm_maxspeed.notna().mean(),
                      "county_unpaved_n": int(((d6.class_grp == "County") & (d6.surface == "Unpaved")).sum()),
                      "county_paved_n": int(((d6.class_grp == "County") & (d6.surface == "Paved")).sum())}
    dfs[GEO_THR] = d6

    # --------------------------------------------------------- validation
    syn, fp = synthetic_test(rng)
    R["synthetic"], R["false_pos"] = syn, fp
    tick("synthetic validation")

    # real examples: sharp, plausible (not cul-de-sac / ring), well-digitised
    cand = d6[(d6.class_grp == "County") & (d6.rd_design == "Single Carriageway") & (~d6.closed) & (d6.length >= 40) & (d6.defl >= 45) &
              (d6.radius_ft >= 100) & (d6.radius_ft <= 300) & (d6.vert_spacing_m <= 15)].copy()
    ex = []
    osm_idx = gpd.GeoDataFrame(oi)
    def osm_radius_at(r):
        pt = Point(r.pmin_x, r.pmin_y)
        near = osm_idx[osm_idx.distance(pt) < 25]
        if not len(near):
            return np.nan
        w = near.iloc[int(np.argmin(near.distance(pt).values))]
        ckw = chain_kappa(np.asarray(w.geometry.coords)[:, :2])
        if ckw is None:
            return np.nan
        dd = np.hypot(ckw["P"][:, 0] - r.pmin_x, ckw["P"][:, 1] - r.pmin_y)
        sel = (dd < 30) & ckw["valid"]
        return float((1 / np.maximum(np.abs(ckw["kap"][sel]), 1e-9)).min() / FT) if sel.any() else np.nan

    for county, surf in (("Benton", "Paved"), ("Washington", "Unpaved"), ("Benton", "Unpaved")):
        sub = cand[(cand.county == county) & (cand.surface == surf)].sort_values("radius_ft")
        if len(sub) == 0:
            continue
        pick, pick_r, tried = None, np.nan, 0
        for _, r in sub.head(60).iterrows():      # first candidate whose OSM geometry independently agrees within x0.67-1.5
            orr = osm_radius_at(r)
            tried += 1
            if pick is None:
                pick, pick_r = r, orr
            if not math.isnan(orr) and 0.67 <= orr / r.radius_ft <= 1.5:
                pick, pick_r = r, orr
                break
        r, osm_r = pick, pick_r
        ex.append(dict(county=county, surface=surf, road=r["name"], lat=f"{r.lat:.6f}", lon=f"{r.lon:.6f}", radius_ft_acf=round(r.radius_ft, 0),
                       deflection_deg=round(r.defl, 0), length_m=round(r.length, 0), vertex_spacing_m=round(r.vert_spacing_m, 1),
                       osm_way_radius_ft_same_algorithm=None if math.isnan(osm_r) else round(osm_r, 0), candidates_tried=tried,
                       osm_link=f"https://www.openstreetmap.org/?mlat={r.lat:.6f}&mlon={r.lon:.6f}#map=19/{r.lat:.6f}/{r.lon:.6f}",
                       gmaps=f"https://www.google.com/maps/@{r.lat:.6f},{r.lon:.6f},19z/data=!3m1!1e3"))
    R["examples"] = ex
    tick("examples")

    # -------------------------------------------------------------- outputs
    geoms = []
    for r, (i_, row) in zip(rows600, d6.iterrows()):
        xs, ys = tr.transform(r["P"][:, 0], r["P"][:, 1])
        geoms.append(LineString(np.c_[xs, ys]) if len(xs) >= 2 else Point(xs[0], ys[0]))
    ids = [f"{FIPS_BY_NAME[c]}-{ci}-{k}" for k, (c, ci) in enumerate(zip(d6.county, d6.chain))]
    out = gpd.GeoDataFrame({
        "id": ids, "county": d6.county.values, "road_name": d6["name"].replace("", None).values, "surface": d6.surface.str.lower().values,
        "radius_ft_est": d6.radius_ft.round(1).values, "deflection_deg": d6.defl.round(1).values, "length_m": d6.length.round(1).values,
        "screening_mph_paved_wet": d6.screening_mph_paved_wet.round(1).values, "screening_mph_unpaved": d6.screening_mph_unpaved.round(1).values,
        "screening_mph_unpaved_f008": d6.screening_mph_unpaved_f008.round(1).values,
        "rd_class": d6.rd_class.values, "rd_design": d6.rd_design.values, "radius_ft_median_in_curve": (d6.rmed_m / FT).round(1).values,
        "lt300ft_30m": d6.has_lt300.values, "lt150ft_30m": d6.has_lt150.values, "turn_dir": d6.side.values, "closed_loop": d6.closed.values,
        "local_vertex_spacing_m": d6.vert_spacing_m.round(1).values, "lat": d6.lat.round(6).values, "lon": d6.lon.round(6).values,
        "osm_id": d6.osm_id.values, "osm_maxspeed": d6.osm_maxspeed.values, "osm_surface": d6.osm_surface.values,
        "quality_flags": d6.quality_flags.values,
        "screening_note": "screening assumption e=0.02,f=0.15/0.10/0.08 - NOT a legal advisory speed",
    }, geometry=geoms, crs=4326)
    out.to_file(f"{OUT}/curves.geojson", driver="GeoJSON", COORDINATE_PRECISION=6)
    tick("geojson written")
    R["times"] = TIMES
    write_summary(R, g, out)
    tick("summary written")


FIPS_BY_NAME = {v: k for k, v in FIPS.items()}



# ================================================================ summary
def write_summary(R, g, out):
    L = []
    A = L.append
    f = R["fetch"]
    A("# RydAR curve-screening prototype — Benton + Washington Counties, AR\n")
    A(f"Generated {time.strftime('%Y-%m-%d %H:%M:%S %Z')} by `/tmp/rydar_curves/build_curves.py`. "
      "**All speeds below are screening assumptions (AASHTO simple-curve formula), NOT legal advisory speeds.**\n")

    A("## 1. Data pulled\n")
    A(f"* Centerlines: `{LAYER}` (ROADS_ACF, ArcGIS Server {f['service_info']['currentVersion']}), native SR EPSG:26915.")
    A(f"* Query `where`: `{WHERE}` — FIPS fields are **3-digit** (`007`,`143`), not `05007`/`05143`; `ah_county` is null on every row I sampled (0 rows match 'Benton%'/'Washington%').")
    A(f"* **maxRecordCount = {f['service_info']['maxRecordCount']}** per request (pagination via `resultOffset` + `orderByFields=objectid` works; "
      f"`supportedQueryFormats` JSON/geoJSON/PBF). Server count for union where = {f['server_count_union']:,}; "
      f"{f['pages']} pages fetched (page size min/max {f['page_sizes_min_max']}); rows fetched {f['rows_fetched']:,}; unique objectid {f['rows_unique_objectid']:,}; null geometry {f['null_geometry']}; fetch retries/failures logged: {len(f['fetch_failures'])}.")
    A(f"* Count by FIPS field: " + "; ".join(f"{k}: cn_r_fips={v['cn_r_fips']:,}, cn_l_fips={v['cn_l_fips']:,}" for k, v in f["fips_counts"].items()) + ".")
    A(f"* County assignment used: cn_r_fips, else cn_l_fips, else `meta_id`. Records kept: {R['n_records']:,} (unassignable: {R['n_assigned_none']}). "
      f"Rows with different left/right county FIPS (boundary roads): {R['boundary_lr_mismatch']}. Rows where my county != `meta_id` county: {R['fips_vs_meta_id_disagree']}. "
      "Some kept rows are in OK/MO (state_l/state_r) next to the border.")
    A("* Full field list (name, type, length):\n")
    A("```\n" + "\n".join(f"{n:18s} {t.replace('esriFieldType','')}  {ln or ''}" for n, t, ln in R["fields"]) + "\n```")
    A("Notes: there is **no `rd_name` field**; road name is `pstr_fulnam` (also `a1/a2/a3_fulnam` alternates). No speed-limit field of any kind exists in the layer. "
      "Extra fields: `rd_design` (Single/Dual Carriageway, ramps…), `ah_*` (ARDOT linear-ref, blank for these counties), `date_ed`.\n")
    A(f"* `date_ed` (only edit-date field; string YYYYMMDD) range: **{min(R['date_ed'])} – {max(R['date_ed'])}**; distinct values and row counts: {R['date_ed']}. "
      "These look like batch stamps from county-level loads rather than per-feature edit times.\n")
    A(md_table(R["date_ed_by_county"], index=False))

    A("\n## 2. Records and miles (centerlines)\n")
    A("Counts by `rd_class` × `rd_surftyp` per county:\n")
    A(md_table(R["cnt_class_surf"]))
    A("\nMiles (computed in UTM 15N; ratio to server `st_length(shape)` = %.5f):\n" % R["len_ratio_utm_over_st_length"])
    A(md_table(R["mi_class_surf"], nd=1))
    A("\nMiles by surface, all classes:\n")
    A(md_table(R["mi_surf"]))
    A("\nCounty-class (`rd_class='County'`) subset — segment counts and miles:\n")
    A(md_table(R["cnt_county_roads"]))
    A("")
    A(md_table(R["mi_county_roads"]))
    A(f"\n`rd_design` counts: {R['design_counts']}\n")

    v = R["vsp"]
    A("## 3. Digitization vertex spacing (original ACF vertices)\n")
    A(f"* {v['n_gaps']:,} vertex gaps; **median {v['median']:.1f} m**, p10 {v['p10']:.1f} m, p90 {v['p90']:.1f} m; share of gaps >20 m: {100*v['frac_gt20']:.1f}%; >50 m: {100*v['frac_gt50']:.1f}%; mean vertices per segment {v['mean_vertices_per_segment']:.1f}.")
    A(f"* Median local vertex spacing in windows around the detected <600 ft curves: {R['curve_vsp_median']:.1f} m.\n")
    A(md_table(R["vsp_by"], index=False))
    A("\nCurve density vs chain median vertex spacing (R<600 ft, ≥30 m):\n")
    A(md_table(R["vsp_effect"], index=False))
    A("\nSensitivity of counts to method choices:\n")
    A(md_table(R["sens"], index=False))

    A("\n## 4. Curves detected\n")
    A(f"Method: UTM 15N (EPSG:26915) → merge same-name/class/surface/design segments at 2-way nodes ({R['n_chains']:,} chains from {R['n_records']:,} segments) → resample every {DS:g} m → "
      f"signed Menger curvature of (i−k, i, i+k) with outer points {WIN:g} m apart along the arc (±{WIN/2:g} m) → {SMOOTH}-sample moving average of curvature ({SMOOTH*DS:g} m) → "
      f"contiguous same-direction stretch with R<threshold for ≥{MIN_LEN:g} m. Radius reported = minimum smoothed radius in the stretch; deflection = summed heading change over the stretch. "
      "No estimate within 20 m of a chain end (open chains). Main run time: %.0f s.\n" % R["time_detect_main_s"])
    A("Number of curves (per threshold; 800/1700 ft are supplementary for the speed buckets only):\n")
    A("| R threshold | curves |\n|---|---|\n" + "\n".join(f"| <{t} ft | {n:,} |" for t, n in R["n_curves"].items()))
    A("\nBy county × class group × surface:\n")
    A(md_table(R["curve_counts"]))
    A("\nBy county × rd_class × surface (R<600 ft):\n")
    A(md_table(R["curve_by_class_600"]))
    A(f"\nR<600 ft curves by `rd_design`: {R['design_curves_600']}; closed loops (cul-de-sacs/roundabouts): {R['closed_curves_600']}.\n")
    A("Radius distribution of detected curves (ft; radius_ft_est = min smoothed radius in stretch):\n")
    A(md_table(R["curve_dist"], index=False))
    A(f"\nQuality flags on the {len(out):,} R<600 ft curves (heuristic; a curve can have several): {R['flag_counts_600']}. Curves with no flag ('clean'): {R['clean_n_600']:,}.\n")
    A(md_table(R["clean_counts_600"]))
    A("\nCurve density per 100 road-miles:\n")
    A(md_table(R["density"], index=False, nd=2))

    A("\n## 5. Method validation\n")
    A("(a) Synthetic 90° circular arc with 80 m tangents each side, vertices every 10 m or 25 m, Gaussian noise (σ per axis) on every vertex, 200 trials/cell. "
      "`arc` = median radius over the arc interior; `pipeline` = what the app would report (min radius in a <600 ft stretch overlapping the arc).\n")
    A(md_table(R["synthetic"], index=False, nd=2))
    A("\nFalse positives on a perfectly straight road with the same vertex noise:\n")
    A(md_table(R["false_pos"], index=False, nd=3))
    A("\n(b) Real examples (sharp, County-class, single carriageway, deflection ≥45°, 100–300 ft, vertex spacing ≤15 m). "
      "Last radius column re-runs the identical algorithm on the nearest OSM way as an independent geometry check. These are NOT verified against imagery by this script.\n")
    A(md_table(pd.DataFrame(R["examples"]).drop(columns=["gmaps"]), index=False, nd=1))
    A("\nSatellite links:\n" + "\n".join(f"* {e['road']} ({e['county']}, {e['surface']}): {e['gmaps']}" for e in R["examples"]))

    A("\n## 6. Screening speeds\n")
    A("V = sqrt(15·R·(e+f)), R in ft, V in mph, e = 0.02 assumed, f = 0.15 (paved wet design assumption), 0.10 and 0.08 (unpaved assumptions). "
      "**Screening assumption only — not a legal or engineering advisory speed.**\n")
    A("Radius at which each speed is reached:\n")
    A(md_table(R["speed_breaks"], index=False, nd=0))
    A("\nCurves below each speed (R_thr = detection cutoff; paved rows use f=0.15, unpaved rows f=0.10 and f=0.08; "
      "bucket counts are capped by the detection cutoff — paved '<45 mph' needs R<794 ft (only the 800-ft run is complete); unpaved '<45 mph' needs R<1,125 ft (f=0.10) / 1,350 ft (f=0.08) so only the 1,700-ft run is complete, and long-radius detections are the most noise-sensitive):\n")
    A(md_table(R["speed_counts"], index=False, nd=1))

    od = R["osm"]
    A("\n## 7. OpenStreetMap (Geofabrik arkansas-latest.osm.pbf, md5 c28afa97… verified against .md5)\n")
    A(f"* Read via pyogrio/GDAL OSM driver, layer `lines`, `highway IS NOT NULL`, bbox of the two counties: {od['bbox_ways_read']:,} ways; after clipping to TIGERweb county polygons: {od['ways_clipped_to_two_counties']:,} line pieces. "
      f"Drivable road classes (motorway…unclassified, residential, living_street, track + links; excludes service/footway/path): {od['road_ways']:,} pieces, {od['road_km']:,.0f} km.")
    A(f"* `ah_*` fields non-null counts (all 12 columns): {R['ah_nonnull']}.")
    A(f"* `maxspeed` values on OSM ways matched to ACF County-class roads: {od['county_maxspeed_dist']}.")
    A(f"* Tag totals on those road pieces: {od['tag_totals']}. `curve=*` values: {od['curve_tag_values']}. Top `surface` values: {od['surface_values']}. Top `maxspeed` values: {od['maxspeed_values']}.\n")
    A("Tag coverage by OSM highway class (percent of ways):\n")
    A(md_table(od["by_highway"], nd=1))
    A("\nLength-weighted coverage on OSM roads matched (≤15 m, 50 m sample points) to ACF centerlines, split by ACF surface and class group "
      f"({od['sample_points']:,} sample points, {od['sample_matched_pct']:.1f}% matched to any ACF line):\n")
    A(md_table(od["acf_matched"], index=False, nd=1))
    p = od["proxy"]
    A(f"\nOSM-only proxy for county roads (tertiary/unclassified/residential/track): {p['ways']:,} ways, maxspeed on {p['maxspeed_pct']:.1f}%, surface on {p['surface_pct']:.1f}%. "
      f"Only unclassified+track ({p['unclassified_track_ways']:,} ways): maxspeed {p['unclass_track_maxspeed_pct']:.1f}%, surface {p['unclass_track_surface_pct']:.1f}%.")
    co = R["curve_osm"]
    A(f"\nDetected R<600 ft curves vs OSM (nearest drivable OSM way ≤20 m): matched {co['matched_pct']:.1f}%; with `maxspeed` {co['maxspeed_pct_of_all']:.1f}%; with `surface` {co['surface_pct_of_all']:.1f}%; "
      f"County-class paved (n={co['county_paved_n']}) maxspeed {co['county_paved_maxspeed_pct']:.1f}%; County-class unpaved (n={co['county_unpaved_n']}) maxspeed {co['county_unpaved_maxspeed_pct']:.1f}%.\n")

    A("\n## 8. Posted speed limits and statute\n")
    A("* ACF layer 18: **no speed-limit attribute** (see field list). OSM: coverage numbers above (`maxspeed`).\n"
      "* Ark. Code Ann. § 27-51-216(b): a county judge may set speed limits on county roads; **if none is set, the limit is 40 mph** on the county road (\"county road\" = public road that is not a state highway, interstate or city street). "
      "Speeding >15 mph over is a Class C misdemeanor (§ 27-51-216(c)(2)). Traffic-control devices must conform to the MUTCD adopted by the State Highway Commission (§ 27-51-216(d)). Enacted by Acts 2007, No. 667 (before that, 65 mph per the AAC road-law guide).\n"
      "* Ark. Code Ann. § 27-51-201(a) (reasonable-and-prudent rule) and (d) (reduce speed approaching/going around a curve, narrow or winding roadway) apply regardless of any limit. "
      "As retrieved (Justia 2025 / Syfert, effective 7/1/2020 version), § 27-51-201(c) no longer contains a general 60/65 mph rural number for cars: it lists 30 mph urban district, 50 mph trucks ≥1.5 ton \"in other locations\", and 30 mph oversize.\n"
      "* **App assumption when no posted limit exists on a county road: 40 mph (§ 27-51-216(b)(2))**, labelled as a statutory default; for state/city roads there is no equivalent simple default — treat as unknown and do not display a limit. "
      "A posted/OSM `maxspeed` overrides it. Statute text was obtained from secondary publishers (Justia/FindLaw/Syfert/AAC guide) because direct fetch of Justia returned HTTP 403; verify against the official Arkansas Code before shipping.\n")

    A("\n## 9. Licensing\n")
    A("* **Arkansas GIS Office ROADS_ACF**: the ArcGIS Hub item metadata (item `3c16bf0bbd7547ffb735fa2dba4cdcfc`, \"Road Centerline File\", source 'Arkansas GIS Office') has `license: none`, empty `licenseInfo`, empty `accessInformation`; the MapServer has empty `copyrightText`. "
      "I found **no explicit license text** for this layer, so the terms are unstated; do not assume CC0/public-domain. Get written confirmation from the Arkansas GIS Office (and check the portal's disclaimer page) before commercial redistribution. "
      "The item description states the ACF standard requires ≤10 m horizontal accuracy (NSSDA).\n"
      "* **OpenStreetMap**: ODbL 1.0 — © OpenStreetMap contributors. Required: visible attribution (\"© OpenStreetMap contributors\" with link to https://www.openstreetmap.org/copyright), "
      "share-alike for a publicly used *derived database* (e.g. a curves layer built with OSM tags must be offered under ODbL; a 'Produced Work' such as a map image only needs attribution), keep ODbL notice, and keep it open (no technical restrictions). "
      "Geofabrik extracts carry the same license. Mixed ACF+OSM data may create a share-alike obligation for the merged database — the exported `osm_*` columns in curves.geojson are OSM-derived.\n")

    A("\n## 10. Run info\n")
    A("Timings (cumulative seconds since start): " + json.dumps(R["times"]) + "\n")
    A(f"Fetch failures/retries logged: {f['fetch_failures'][:5]}\n")
    open(f"{OUT}/SUMMARY.md", "w").write("\n".join(L))
    # machine readable
    def ser(o):
        if isinstance(o, pd.DataFrame):
            return o.reset_index().to_dict("records")
        if isinstance(o, (np.integer,)):
            return int(o)
        if isinstance(o, (np.floating,)):
            return float(o)
        return str(o)
    json.dump({k: v for k, v in R.items() if k not in ("fetch",)}, open(f"{OUT}/results.json", "w"), default=ser, indent=1)


if __name__ == "__main__":
    main()
