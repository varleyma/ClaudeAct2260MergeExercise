"""
Design 1: stacked ring event-study dataset.

For each dated high-confidence investor purchase ("event"), pair it with every
CRIM sale within 1000m and record distance, ring, and event time. No deflation
is applied; analysis-side filters are provided as flags, not imposed.

Inputs (Dropbox, READ ONLY):
    data/cleaned/combined_parcels_uniquematch_tracts.csv   (investor parcels)
    data/third_party/nearby_sales_1000m_uniquematch_combined.csv (sales pool)

Outputs (GitHub repo):
    data/design1/design1_events.csv       one row per event
    data/design1/design1_sale_event_pairs.csv   one row per (event x sale within 1000m)

Event definition: investor parcels sharing the same centroid (6 dp) AND the
same sale date are one event (e.g. two condo units bought together).

Rings: near = 0-250m, gap = 250-400m (buffer, usually excluded), far = 400-1000m.
Distances are centroid-to-centroid (haversine).

Notes for analysis:
  - flag_junk_date / flag_nominal_price mark CRIM data-quality issues; filter in R.
  - sale_is_investor_parcel marks sales that are themselves matched investor
    parcels (any confidence tier) -- exclude for a market-only outcome sample.
  - CRIM stores only each parcel's LAST sale: earlier sales are censored by
    later resales. Prefer within-tract/time comparisons; see project log.
"""

import csv, math, os
from collections import defaultdict
from datetime import datetime

DROPBOX = r"C:\Users\mva284\Dropbox\ClaudeAct2260MergeExercise"
REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
EVENTS_SRC = os.path.join(DROPBOX, "data", "cleaned", "combined_parcels_uniquematch_tracts.csv")
SALES_SRC = os.path.join(DROPBOX, "data", "third_party", "nearby_sales_1000m_uniquematch_combined.csv")
OUT_DIR = os.path.join(REPO, "data", "design1")

RADIUS_M = 1000.0
NEAR_M, GAP_M = 250.0, 400.0
CELL = 0.01  # degrees; > 1000m everywhere in PR


def haversine_m(lon1, lat1, lon2, lat2):
    R = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


def parse_date(s):
    try:
        d = datetime.strptime((s or "").strip(), "%Y-%m-%d")
        return d if 1950 <= d.year <= 2026 else None
    except ValueError:
        return None


def fnum(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return None


def main():
    csv.field_size_limit(10_000_000)
    os.makedirs(OUT_DIR, exist_ok=True)

    # ---- events: group dated investor parcels by (location, date) ----
    groups = defaultdict(list)
    n_undated = 0
    for r in csv.DictReader(open(EVENTS_SRC, newline="", encoding="utf-8")):
        d = parse_date(r.get("SALESDATE"))
        x, y = fnum(r.get("INSIDE_X")), fnum(r.get("INSIDE_Y"))
        if d is None or x is None or y is None:
            n_undated += 1
            continue
        groups[(round(x, 6), round(y, 6), d.strftime("%Y-%m-%d"))].append(r)

    events = []
    for i, ((lon, lat, ds), parcels) in enumerate(sorted(groups.items(), key=lambda kv: (kv[0][2], kv[0][0], kv[0][1]))):
        p0 = parcels[0]
        amts = [fnum(p.get("SALESAMT")) for p in parcels]
        events.append({
            "event_id": f"E{i+1:04d}",
            "event_date": ds,
            "lon": lon, "lat": lat,
            "n_parcels_in_event": len(parcels),
            "catastros": ";".join(p["CATASTRO"].strip() for p in parcels),
            "buyer": p0.get("BYERNAME", "").strip(),
            "municipio": p0.get("MUNICIPIO", ""),
            "tract_geoid": p0.get("tract_geoid", ""),
            "zcta": p0.get("zcta", ""),
            "base_source": ";".join(sorted({p.get("base_source", "") for p in parcels})),
            "total_investor_salesamt": round(sum(a for a in amts if a), 2),
            "is_subunit": p0.get("is_subunit", ""),
        })
    print(f"events: {len(events)}  (investor parcels dropped for missing/junk date or coords: {n_undated})")

    # ---- event-level contamination: other events within 1000m ----
    for e in events:
        e["_dt"] = datetime.strptime(e["event_date"], "%Y-%m-%d")
    for e in events:
        near = []
        for o in events:
            if o["event_id"] == e["event_id"]:
                continue
            if abs(o["lon"] - e["lon"]) > 0.011 or abs(o["lat"] - e["lat"]) > 0.010:
                continue
            dm = haversine_m(e["lon"], e["lat"], o["lon"], o["lat"])
            if dm <= RADIUS_M:
                near.append((dm, o))
        e["n_other_events_within_1000m"] = len(near)
        e["min_dist_other_event_m"] = round(min(n[0] for n in near), 1) if near else ""
        e["clean_event_1000m"] = "True" if not near else "False"

    # ---- sales pool, grid-bucketed ----
    grid = defaultdict(list)
    sales = []
    for r in csv.DictReader(open(SALES_SRC, newline="", encoding="utf-8")):
        x, y = fnum(r.get("INSIDE_X")), fnum(r.get("INSIDE_Y"))
        if x is None or y is None:
            continue
        s = {
            "CATASTRO": r["CATASTRO"].strip(), "lon": x, "lat": y,
            "sale_date": r.get("SALESDATE", ""), "SALESAMT": r.get("SALESAMT", ""),
            "MUNICIPIO": r.get("MUNICIPIO", ""), "tract_geoid": r.get("tract_geoid", ""),
            "CABIDA": r.get("CABIDA", ""), "LAND": r.get("LAND", ""),
            "STRUCTURE": r.get("STRUCTURE", ""), "TOTALVAL": r.get("TOTALVAL", ""),
            "SELLERNAME": r.get("SELLERNAME", ""), "BYERNAME": r.get("BYERNAME", ""),
            "is_subunit": r.get("is_subunit", ""), "seller_is_corporate": r.get("seller_is_corporate", ""),
            "vacant_land": r.get("vacant_land", ""),
            "sale_is_investor_parcel": r.get("neighbor_is_investor_parcel", ""),
        }
        sales.append(s)
        grid[(int(x / CELL), int(y / CELL))].append(len(sales) - 1)
    print(f"sales pool: {len(sales)}")

    # ---- pair construction ----
    pair_cols = ["event_id", "event_date", "sale_catastro", "sale_date", "dist_m", "ring",
                 "event_time_months", "SALESAMT", "MUNICIPIO", "tract_geoid",
                 "CABIDA", "LAND", "STRUCTURE", "TOTALVAL", "SELLERNAME", "BYERNAME",
                 "is_subunit", "seller_is_corporate", "vacant_land",
                 "sale_is_investor_parcel", "flag_nominal_price", "flag_junk_date"]
    n_pairs = 0
    sale_event_count = defaultdict(int)
    pairs_path = os.path.join(OUT_DIR, "design1_sale_event_pairs.csv")
    with open(pairs_path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=pair_cols)
        w.writeheader()
        for e in events:
            own = set(e["catastros"].split(";"))
            cx, cy = int(e["lon"] / CELL), int(e["lat"] / CELL)
            for gx in (cx - 1, cx, cx + 1):
                for gy in (cy - 1, cy, cy + 1):
                    for idx in grid.get((gx, gy), ()):
                        s = sales[idx]
                        if s["CATASTRO"] in own:
                            continue
                        dm = haversine_m(e["lon"], e["lat"], s["lon"], s["lat"])
                        if dm > RADIUS_M:
                            continue
                        sd = parse_date(s["sale_date"])
                        etm = ""
                        if sd:
                            etm = (sd.year * 12 + sd.month) - (e["_dt"].year * 12 + e["_dt"].month)
                        amt = fnum(s["SALESAMT"])
                        ring = "near_0_250" if dm <= NEAR_M else ("gap_250_400" if dm <= GAP_M else "far_400_1000")
                        row = {k: s.get(k, "") for k in pair_cols if k in s}
                        row.update({
                            "event_id": e["event_id"], "event_date": e["event_date"],
                            "sale_catastro": s["CATASTRO"], "sale_date": s["sale_date"],
                            "dist_m": round(dm, 1), "ring": ring, "event_time_months": etm,
                            "flag_nominal_price": "True" if (amt is not None and amt < 10000) else "False",
                            "flag_junk_date": "True" if sd is None else "False",
                        })
                        w.writerow(row)
                        n_pairs += 1
                        sale_event_count[s["CATASTRO"]] += 1
    print(f"pairs written: {n_pairs}")

    # ---- events file ----
    ev_cols = ["event_id", "event_date", "lon", "lat", "n_parcels_in_event", "catastros",
               "buyer", "municipio", "tract_geoid", "zcta", "base_source",
               "total_investor_salesamt", "is_subunit",
               "n_other_events_within_1000m", "min_dist_other_event_m", "clean_event_1000m",
               "n_sales_within_1000m"]
    ev_path = os.path.join(OUT_DIR, "design1_events.csv")
    with open(ev_path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=ev_cols, extrasaction="ignore")
        w.writeheader()
        for e in events:
            own = set(e["catastros"].split(";"))
            # recount from pair pass would need a second structure; approximate via grid
            n_s = 0
            cx, cy = int(e["lon"] / CELL), int(e["lat"] / CELL)
            for gx in (cx - 1, cx, cx + 1):
                for gy in (cy - 1, cy, cy + 1):
                    for idx in grid.get((gx, gy), ()):
                        s = sales[idx]
                        if s["CATASTRO"] not in own and haversine_m(e["lon"], e["lat"], s["lon"], s["lat"]) <= RADIUS_M:
                            n_s += 1
            e["n_sales_within_1000m"] = n_s
            w.writerow(e)

    clean = sum(1 for e in events if e["clean_event_1000m"] == "True")
    print(f"clean events (no other event within 1000m): {clean}/{len(events)}")
    print(f"outputs:\n  {ev_path}\n  {pairs_path}")


if __name__ == "__main__":
    main()
