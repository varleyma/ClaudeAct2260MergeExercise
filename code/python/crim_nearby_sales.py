"""
Nearby property sales around Act 22/60 investor parcels (CRIM spatial scrape).

For each investor parcel (from the enriched CRIM file), query the CRIM Parcelas
REST layer for all parcels within a buffer radius, keep the ones that have a
recorded sale, and build a DE-DUPLICATED pool of nearby sales -- each neighbor
parcel appears once, tagged with:

    nearest_investor_catastro     closest investor parcel
    nearest_investor_dist_m       distance to it (meters, centroid-to-centroid)
    n_investor_parcels_within     # of investor parcels within `radius` of it
    nearest_investor_is_unique    is_unique_match flag of that nearest investor parcel
    neighbor_is_investor_parcel   True if the neighbor is itself an investor parcel

Query points are de-duplicated by centroid so each location is hit once; the
per-location investor-parcel counts are still weighted by how many investor
parcels sit at that location (e.g. condo units sharing a centroid).

Usage:
    crim_nearby_sales.py --base unique --radius 250 --out <path>
    crim_nearby_sales.py --base all    --radius 250 --out <path>
"""

import argparse, csv, json, math, os, pickle, sys, time, urllib.parse, urllib.request


def keep_awake():
    """Prevent idle system sleep while this process runs (Windows only).

    Uses SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED); the flag is
    cleared automatically when the process exits, so nothing persists. Does NOT
    override a lid-close sleep action -- that's a separate power-plan setting.
    """
    if sys.platform != "win32":
        return
    try:
        import ctypes
        ES_CONTINUOUS = 0x80000000
        ES_SYSTEM_REQUIRED = 0x00000001
        ctypes.windll.kernel32.SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)
        print("[keep-awake] idle sleep suppressed for the duration of this run")
    except Exception as e:  # noqa
        print(f"[keep-awake] could not set state: {e}")

PROXY = "https://catastro.crimpr.net/proxy/proxy.ashx?"
LAYER = "https://catastro.crimpr.net/server/rest/services/Parcelario/Parcelas/MapServer/654/query"
REFERER = "https://catastro.crimpr.net/cdprpc/"

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ENRICHED = os.path.join(ROOT, "data", "third_party", "crim_parcel_enriched.csv")

NEIGHBOR_FIELDS = [
    "CATASTRO", "MUNICIPIO", "CONTACT", "DIRECCION_FISICA", "CABIDA", "LAND",
    "STRUCTURE", "TOTALVAL", "DEEDBOOK", "DEEDPAGE", "ESTATE", "DEEDNUM",
    "SALESAMT", "SALESDTTM", "SELLERNAME", "BYERNAME", "INSIDE_X", "INSIDE_Y",
]
PAGE = 2000


def haversine_m(lon1, lat1, lon2, lat2):
    R = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


def epoch_ms_to_date(v):
    if v in (None, ""):
        return ""
    try:
        from datetime import datetime, timezone
        return datetime.fromtimestamp(int(v) / 1000, tz=timezone.utc).strftime("%Y-%m-%d")
    except Exception:
        return str(v)


def _post(params, retries=4):
    body = urllib.parse.urlencode(params).encode("utf-8")
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(PROXY + LAYER, data=body, method="POST", headers={
                "Referer": REFERER,
                "Content-Type": "application/x-www-form-urlencoded",
                "User-Agent": "Mozilla/5.0 (research; nearby sales)",
            })
            with urllib.request.urlopen(req, timeout=90) as r:
                d = json.loads(r.read().decode("utf-8"))
            if "error" in d:
                last = d["error"]
                time.sleep(2 * (attempt + 1))
                continue
            return d
        except Exception as e:  # noqa
            last = str(e)
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"query failed after {retries} tries: {last}")


def buffer_query(lon, lat, meters):
    """Return all parcel attribute dicts within `meters` of the point (paginated)."""
    base = {
        "geometry": json.dumps({"x": lon, "y": lat, "spatialReference": {"wkid": 4326}}),
        "geometryType": "esriGeometryPoint",
        "inSR": "4326",
        "distance": str(meters),
        "units": "esriSRUnit_Meter",
        "spatialRel": "esriSpatialRelIntersects",
        "outFields": ",".join(NEIGHBOR_FIELDS),
        "returnGeometry": "false",
        "f": "json",
    }
    out = []
    offset = 0
    while True:
        params = dict(base, resultOffset=str(offset), resultRecordCount=str(PAGE))
        d = _post(params)
        feats = d.get("features", [])
        out.extend(f["attributes"] for f in feats)
        if d.get("exceededTransferLimit") and feats:
            offset += len(feats)
            continue
        break
    return out


def load_base(enriched_path=ENRICHED):
    """Return (base_points, investor_catastros).

    base_points: list of dicts {lon,lat,parcels:[{catastro,is_unique}]}
    investor_catastros: set of all investor CATASTROs.
    """
    by_loc = {}
    investor = set()
    with open(enriched_path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            c = (row.get("CATASTRO") or "").strip()
            if c:
                investor.add(c)
            x = (row.get("INSIDE_X") or "").strip()
            y = (row.get("INSIDE_Y") or "").strip()
            if not x or not y:
                continue
            key = (round(float(x), 6), round(float(y), 6))
            uniq = (row.get("is_unique_match") == "True")
            by_loc.setdefault(key, {"lon": float(x), "lat": float(y), "parcels": []})
            by_loc[key]["parcels"].append({"catastro": c, "is_unique": uniq})
    return list(by_loc.values()), investor


def loc_key(pt):
    return f"{round(pt['lon'], 6)},{round(pt['lat'], 6)}"


def save_checkpoint(state_path, out_path, done, pool, header):
    """Atomically persist resume state (pickle) and human-readable partial CSV."""
    tmp = state_path + ".tmp"
    with open(tmp, "wb") as fh:
        pickle.dump({"done": done, "pool": pool}, fh, protocol=pickle.HIGHEST_PROTOCOL)
    os.replace(tmp, state_path)  # atomic: state stays consistent across crashes

    tmp_csv = out_path + ".tmp"
    with open(tmp_csv, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=header, extrasaction="ignore")
        w.writeheader()
        for rec in pool.values():
            row = dict(rec)
            if row.get("nearest_investor_dist_m") is not None:
                row["nearest_investor_dist_m"] = round(row["nearest_investor_dist_m"], 1)
            w.writerow(row)
    os.replace(tmp_csv, out_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", choices=["unique", "all"], required=True)
    ap.add_argument("--radius", type=float, default=250)
    ap.add_argument("--sleep", type=float, default=0.3)
    ap.add_argument("--out", required=True)
    ap.add_argument("--checkpoint", type=int, default=300, help="save state every N locations")
    ap.add_argument("--fresh", action="store_true", help="ignore any existing checkpoint and restart")
    ap.add_argument("--limit", type=int, default=0, help="debug: only first N locations")
    ap.add_argument("--enriched", default=ENRICHED, help="base parcel file (default: crim_parcel_enriched.csv)")
    args = ap.parse_args()

    keep_awake()

    header = NEIGHBOR_FIELDS + [
        "SALESDATE", "nearest_investor_catastro", "nearest_investor_dist_m",
        "n_investor_parcels_within", "nearest_investor_is_unique",
        "neighbor_is_investor_parcel",
    ]

    points, investor_catastros = load_base(args.enriched)

    if args.base == "unique":
        points = [p for p in points if any(pc["is_unique"] for pc in p["parcels"])]
    if args.limit:
        points = points[: args.limit]

    total = len(points)

    # ---- resume from checkpoint if present ----
    state_path = args.out + ".state.pkl"
    done = set()
    pool = {}
    if os.path.exists(state_path) and not args.fresh:
        try:
            with open(state_path, "rb") as fh:
                st = pickle.load(fh)
            done = st.get("done", set())
            pool = st.get("pool", {})
            print(f"[resume] loaded checkpoint: {len(done)} locations done, pool size {len(pool)}")
        except Exception as e:  # noqa
            print(f"[resume] checkpoint unreadable ({e}); starting fresh")
            done, pool = set(), {}

    print(f"base='{args.base}' radius={args.radius}m  locations: {total}  remaining: {total - len(done)}")
    os.makedirs(os.path.dirname(args.out), exist_ok=True)

    failures = 0
    processed = 0
    for i, pt in enumerate(points, 1):
        k = loc_key(pt)
        if k in done:
            continue
        try:
            feats = buffer_query(pt["lon"], pt["lat"], args.radius)
        except Exception as e:  # noqa
            failures += 1
            print(f"  [WARN] location {i} ({pt['lon']:.5f},{pt['lat']:.5f}) failed: {e}")
            time.sleep(args.sleep)
            continue

        n_inv_here = len(pt["parcels"])
        # representative nearest investor parcel at this location (all share centroid)
        rep = pt["parcels"][0]
        rep_unique = any(pc["is_unique"] for pc in pt["parcels"])

        seen_here = set()
        for a in feats:
            nc = (a.get("CATASTRO") or "").strip()
            if not nc or nc in seen_here:
                continue
            seen_here.add(nc)
            if not a.get("SALESDTTM"):   # sales-only pool
                continue
            nx, ny = a.get("INSIDE_X"), a.get("INSIDE_Y")
            try:
                dist = haversine_m(float(nx), float(ny), pt["lon"], pt["lat"])
            except Exception:
                dist = None

            rec = pool.get(nc)
            if rec is None:
                rec = {fld: a.get(fld) for fld in NEIGHBOR_FIELDS}
                rec["SALESDATE"] = epoch_ms_to_date(a.get("SALESDTTM"))
                rec["nearest_investor_catastro"] = rep["catastro"]
                rec["nearest_investor_dist_m"] = dist
                rec["nearest_investor_is_unique"] = "True" if rep_unique else "False"
                rec["n_investor_parcels_within"] = n_inv_here
                rec["neighbor_is_investor_parcel"] = "True" if nc in investor_catastros else "False"
                pool[nc] = rec
            else:
                rec["n_investor_parcels_within"] += n_inv_here
                if dist is not None and (rec["nearest_investor_dist_m"] is None or dist < rec["nearest_investor_dist_m"]):
                    rec["nearest_investor_dist_m"] = dist
                    rec["nearest_investor_catastro"] = rep["catastro"]
                    rec["nearest_investor_is_unique"] = "True" if rep_unique else "False"

        done.add(k)
        processed += 1

        if processed % args.checkpoint == 0:
            save_checkpoint(state_path, args.out, done, pool, header)
            print(f"  {i}/{total} locations | pool {len(pool)} | failures {failures} | [checkpoint saved]")
        elif i % 250 == 0 or i == total:
            print(f"  {i}/{total} locations | pool {len(pool)} | failures {failures}")
        time.sleep(args.sleep)

    # final write (also refreshes the checkpoint, so re-running is a no-op)
    save_checkpoint(state_path, args.out, done, pool, header)

    only_market = sum(1 for r in pool.values() if r["neighbor_is_investor_parcel"] == "False")
    print(f"\nDONE. nearby-sale parcels: {len(pool)}  (non-investor: {only_market})")
    print(f"  locations queried: {total}  failures: {failures}")
    print(f"  output: {args.out}")


if __name__ == "__main__":
    main()
