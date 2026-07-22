"""
Local nearby-sales ring builder -- replaces per-ring CRIM scraping.

Uses the island-wide parcel snapshot (crim_full_island_scrape.py) to compute a
nearby-sales dataset for ANY radius and base entirely offline, in the same
column format as crim_nearby_sales.py output (so add_investor_sale_cols.py and
flag_property_age_signals.py apply unchanged).

Semantics match the scraped versions: deduplicated pool of parcels WITH a
recorded sale within `radius` of any base location, tagged with the nearest
base parcel, distance, count of base parcels within radius, and whether the
neighbor is itself a base/investor parcel.

Usage:
    build_rings_local.py --base unique --radius 2500 --out <path>
    build_rings_local.py --base all --radius 5000 \
        --enriched <base parcel csv> --out <path>
"""

import argparse, csv, math, os, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from crim_rest_enrich import OUT_FIELDS  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
ISLAND = os.path.join(REPO, "data", "third_party", "crim_parcels_island.csv")
DEFAULT_ENRICHED = os.path.join(REPO, "data", "third_party", "crim_parcel_enriched.csv")

NEIGHBOR_FIELDS = [
    "CATASTRO", "MUNICIPIO", "CONTACT", "DIRECCION_FISICA", "CABIDA", "LAND",
    "STRUCTURE", "TOTALVAL", "DEEDBOOK", "DEEDPAGE", "ESTATE", "DEEDNUM",
    "SALESAMT", "SALESDTTM", "SELLERNAME", "BYERNAME", "INSIDE_X", "INSIDE_Y",
]


def haversine_m(lon1, lat1, lon2, lat2):
    R = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", choices=["unique", "all"], required=True)
    ap.add_argument("--radius", type=float, required=True, help="meters")
    ap.add_argument("--enriched", default=DEFAULT_ENRICHED)
    ap.add_argument("--island", default=ISLAND)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    csv.field_size_limit(10_000_000)

    # grid cell sized to the radius so a 3x3 neighborhood always covers it
    cell_deg = max(args.radius / 111000.0 * 1.1, 0.005)

    # ---- base locations ----
    by_loc, investor = {}, set()
    with open(args.enriched, newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            c = (r.get("CATASTRO") or "").strip()
            if c:
                investor.add(c)
            if args.base == "unique" and r.get("is_unique_match") != "True":
                continue
            try:
                x, y = float(r["INSIDE_X"]), float(r["INSIDE_Y"])
            except (KeyError, TypeError, ValueError):
                continue
            key = (round(x, 6), round(y, 6))
            by_loc.setdefault(key, {"lon": x, "lat": y, "parcels": []})
            by_loc[key]["parcels"].append({"catastro": c, "is_unique": r.get("is_unique_match") == "True"})
    points = list(by_loc.values())
    print(f"base='{args.base}' radius={args.radius:.0f}m  locations: {len(points)}")

    # ---- island sales pool (compact storage: tuples) ----
    print("loading island snapshot (sales only)...")
    IDX = {f: i for i, f in enumerate(NEIGHBOR_FIELDS)}
    sales, grid = [], defaultdict(list)
    n_all = 0
    with open(args.island, newline="", encoding="utf-8") as fh:
        r = csv.DictReader(fh)
        for row in r:
            n_all += 1
            if not (row.get("SALESDTTM") or "").strip():
                continue
            try:
                x, y = float(row["INSIDE_X"]), float(row["INSIDE_Y"])
            except (TypeError, ValueError):
                continue
            rec = tuple(row.get(f, "") for f in NEIGHBOR_FIELDS) + (row.get("SALESDATE", ""),)
            sales.append(rec)
            grid[(int(x / cell_deg), int(y / cell_deg))].append(len(sales) - 1)
    print(f"  island parcels: {n_all:,} | with sale + coords: {len(sales):,}")

    # ---- pool construction (same aggregation as crim_nearby_sales) ----
    pool = {}
    for i, pt in enumerate(points, 1):
        n_inv_here = len(pt["parcels"])
        rep = pt["parcels"][0]
        rep_unique = any(p["is_unique"] for p in pt["parcels"])
        cx, cy = int(pt["lon"] / cell_deg), int(pt["lat"] / cell_deg)
        for gx in (cx - 1, cx, cx + 1):
            for gy in (cy - 1, cy, cy + 1):
                for idx in grid.get((gx, gy), ()):
                    s = sales[idx]
                    try:
                        sx, sy = float(s[IDX["INSIDE_X"]]), float(s[IDX["INSIDE_Y"]])
                    except ValueError:
                        continue
                    dm = haversine_m(pt["lon"], pt["lat"], sx, sy)
                    if dm > args.radius:
                        continue
                    nc = s[IDX["CATASTRO"]].strip()
                    rec = pool.get(nc)
                    if rec is None:
                        rec = {f: s[IDX[f]] for f in NEIGHBOR_FIELDS}
                        rec["SALESDATE"] = s[-1]
                        rec["nearest_investor_catastro"] = rep["catastro"]
                        rec["nearest_investor_dist_m"] = dm
                        rec["nearest_investor_is_unique"] = "True" if rep_unique else "False"
                        rec["n_investor_parcels_within"] = n_inv_here
                        rec["neighbor_is_investor_parcel"] = "True" if nc in investor else "False"
                        pool[nc] = rec
                    else:
                        rec["n_investor_parcels_within"] += n_inv_here
                        if dm < rec["nearest_investor_dist_m"]:
                            rec["nearest_investor_dist_m"] = dm
                            rec["nearest_investor_catastro"] = rep["catastro"]
                            rec["nearest_investor_is_unique"] = "True" if rep_unique else "False"
        if i % 200 == 0 or i == len(points):
            print(f"  {i}/{len(points)} locations | pool {len(pool):,}")

    header = NEIGHBOR_FIELDS + [
        "SALESDATE", "nearest_investor_catastro", "nearest_investor_dist_m",
        "n_investor_parcels_within", "nearest_investor_is_unique",
        "neighbor_is_investor_parcel",
    ]
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=header, extrasaction="ignore")
        w.writeheader()
        for rec in pool.values():
            rec["nearest_investor_dist_m"] = round(rec["nearest_investor_dist_m"], 1)
            w.writerow(rec)

    only_market = sum(1 for r in pool.values() if r["neighbor_is_investor_parcel"] == "False")
    print(f"\nDONE. nearby-sale parcels: {len(pool):,} (non-investor: {only_market:,})")
    print(f"  output: {args.out}")


if __name__ == "__main__":
    main()
