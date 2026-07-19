"""
Placebo events for Design 1: high-value purchases by NON-investor, individual
(non-corporate) buyers, co-located with real investor events (<=250m) but
temporally separated -- a timing placebo within the same micro-areas.

Why co-located: the sales pool only covers 1000m around real investor
locations, so a placebo ring is fully covered only near a real event site.
At <=250m offset the placebo ring is complete out to ~750m; the Stata side
truncates far rings at 750m for both placebo and the matching real baseline.

Selection criteria for placebo events:
  - sale by an individual (non-corporate regex) buyer, parcel not an
    investor-matched parcel, valid date 2013-2023, price within the
    [p25, p95] band of real investor event purchase amounts
  - within 250m of at least one real event location
  - up to N_PLACEBO sampled with a fixed seed (deterministic)

Outputs (repo):
    data/design1/placebo_events.csv
    data/design1/placebo_sale_event_pairs.csv  (same columns as the design1
        pairs + placebo metadata; gitignore if >95MB)
"""

import csv, math, os, random
from collections import defaultdict
from datetime import datetime

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
SALES_SRC = os.path.join(REPO, "data", "third_party", "nearby_sales_1000m_uniquematch_combined.csv")
EVENTS_SRC = os.path.join(REPO, "data", "design1", "design1_events.csv")
OUT_DIR = os.path.join(REPO, "data", "design1")

N_PLACEBO = 1500
RADIUS_M = 1000.0
COLOC_M = 250.0
CELL = 0.01

CORP_RE = __import__("re").compile(
    r"\b(DEVELOP\w*|CONSTRUC\w*|BUILDER\w*|CORP\w*|LLC|INC|CO|COMPANY|SOCIEDAD|"
    r"S\.?E\.?|ASSOCIATES?|PARTNERS?|PROPERTIES|PROPERTY|REALTY|INVESTMENT\w*|"
    r"INVERSION\w*|HOLDINGS?|GROUP|GRUPO|HOMES?|HOM|VENTURES?|ENTERPRISES?|"
    r"TRUST|BANK|BANCO|COOPERATIVA|CRUV|AUTORIDAD|MUNICIPIO|ESTADO)\b")


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

    # ---- real events (dated, decree era) ----
    events = []
    for r in csv.DictReader(open(EVENTS_SRC, newline="", encoding="utf-8")):
        d = parse_date(r["event_date"])
        if d is None or d.year < 2012:
            continue
        events.append({"id": r["event_id"], "lon": float(r["lon"]), "lat": float(r["lat"]),
                       "date": d, "amt": fnum(r.get("total_investor_salesamt"))})
    amts = sorted(a["amt"] for a in events if a["amt"])
    p25 = amts[len(amts) // 4]
    p95 = amts[int(len(amts) * 0.95)]
    print(f"real events: {len(events)} | investor purchase band [p25,p95] = [{p25:,.0f}, {p95:,.0f}]")

    egrid = defaultdict(list)
    for i, e in enumerate(events):
        egrid[(int(e["lon"] / CELL), int(e["lat"] / CELL))].append(i)

    def nearest_event(lon, lat):
        best = (None, float("inf"))
        cx, cy = int(lon / CELL), int(lat / CELL)
        for gx in (cx - 1, cx, cx + 1):
            for gy in (cy - 1, cy, cy + 1):
                for i in egrid.get((gx, gy), ()):
                    dm = haversine_m(lon, lat, events[i]["lon"], events[i]["lat"])
                    if dm < best[1]:
                        best = (i, dm)
        return best

    # ---- sales pool + placebo candidates ----
    sales, grid, candidates = [], defaultdict(list), []
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
        idx = len(sales) - 1
        grid[(int(x / CELL), int(y / CELL))].append(idx)

        # placebo candidacy
        d = parse_date(s["sale_date"])
        amt = fnum(s["SALESAMT"])
        buyer = (s["BYERNAME"] or "").strip().upper()
        if (d and 2013 <= d.year <= 2023 and amt and p25 <= amt <= p95
                and s["sale_is_investor_parcel"] == "False"
                and buyer and not CORP_RE.search(buyer)):
            candidates.append(idx)
    print(f"sales pool: {len(sales)} | placebo candidates (pre-distance): {len(candidates)}")

    # co-location filter + metadata
    placebos = []
    for idx in candidates:
        s = sales[idx]
        ei, dm = nearest_event(s["lon"], s["lat"])
        if ei is None or dm > COLOC_M:
            continue
        e = events[ei]
        sd = parse_date(s["sale_date"])
        placebos.append({
            "sale_idx": idx,
            "months_to_nearest_event": (sd.year * 12 + sd.month) - (e["date"].year * 12 + e["date"].month),
            "nearest_event_id": e["id"], "nearest_event_dist_m": round(dm, 1),
        })
    print(f"co-located candidates (<= {COLOC_M:.0f}m of a real event): {len(placebos)}")

    rng = random.Random(42)
    if len(placebos) > N_PLACEBO:
        placebos = rng.sample(placebos, N_PLACEBO)
        placebos.sort(key=lambda p: p["sale_idx"])
    print(f"sampled placebo events: {len(placebos)}")

    # ---- write events + pairs ----
    ev_cols = ["event_id", "event_date", "lon", "lat", "placebo_salesamt", "buyer",
               "municipio", "tract_geoid", "nearest_event_id", "nearest_event_dist_m",
               "months_to_nearest_event"]
    pair_cols = ["event_id", "event_date", "sale_catastro", "sale_date", "dist_m", "ring",
                 "event_time_months", "SALESAMT", "MUNICIPIO", "tract_geoid",
                 "CABIDA", "LAND", "STRUCTURE", "TOTALVAL", "SELLERNAME", "BYERNAME",
                 "is_subunit", "seller_is_corporate", "vacant_land",
                 "sale_is_investor_parcel", "flag_nominal_price", "flag_junk_date"]

    n_pairs = 0
    with open(os.path.join(OUT_DIR, "placebo_events.csv"), "w", newline="", encoding="utf-8") as fe, \
         open(os.path.join(OUT_DIR, "placebo_sale_event_pairs.csv"), "w", newline="", encoding="utf-8") as fp:
        we = csv.DictWriter(fe, fieldnames=ev_cols)
        wp = csv.DictWriter(fp, fieldnames=pair_cols)
        we.writeheader()
        wp.writeheader()
        for j, p in enumerate(placebos):
            s0 = sales[p["sale_idx"]]
            pid = f"P{j+1:04d}"
            d0 = parse_date(s0["sale_date"])
            we.writerow({
                "event_id": pid, "event_date": s0["sale_date"],
                "lon": round(s0["lon"], 6), "lat": round(s0["lat"], 6),
                "placebo_salesamt": s0["SALESAMT"], "buyer": s0["BYERNAME"].strip(),
                "municipio": s0["MUNICIPIO"], "tract_geoid": s0["tract_geoid"],
                "nearest_event_id": p["nearest_event_id"],
                "nearest_event_dist_m": p["nearest_event_dist_m"],
                "months_to_nearest_event": p["months_to_nearest_event"],
            })
            cx, cy = int(s0["lon"] / CELL), int(s0["lat"] / CELL)
            for gx in (cx - 1, cx, cx + 1):
                for gy in (cy - 1, cy, cy + 1):
                    for idx in grid.get((gx, gy), ()):
                        if idx == p["sale_idx"]:
                            continue
                        s = sales[idx]
                        dm = haversine_m(s0["lon"], s0["lat"], s["lon"], s["lat"])
                        if dm > RADIUS_M:
                            continue
                        sd = parse_date(s["sale_date"])
                        etm = ""
                        if sd:
                            etm = (sd.year * 12 + sd.month) - (d0.year * 12 + d0.month)
                        amt = fnum(s["SALESAMT"])
                        ring = "near_0_250" if dm <= 250 else ("gap_250_400" if dm <= 400 else "far_400_1000")
                        row = {k: s.get(k, "") for k in pair_cols if k in s}
                        row.update({
                            "event_id": pid, "event_date": s0["sale_date"],
                            "sale_catastro": s["CATASTRO"], "sale_date": s["sale_date"],
                            "dist_m": round(dm, 1), "ring": ring, "event_time_months": etm,
                            "flag_nominal_price": "True" if (amt is not None and amt < 10000) else "False",
                            "flag_junk_date": "True" if sd is None else "False",
                        })
                        wp.writerow(row)
                        n_pairs += 1
    print(f"placebo pairs written: {n_pairs}")
    print("outputs: placebo_events.csv, placebo_sale_event_pairs.csv")


if __name__ == "__main__":
    main()
