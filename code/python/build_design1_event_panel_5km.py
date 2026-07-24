"""
5km sale-event pairs for the spatial-decay analysis.

Pairs every dated Design 1 event with all island-snapshot sales within 5,000m,
keeping a SLIM column set (the decay analysis needs prices and distances; the
full hedonics/composition suite already ran at 1km). Ring cutoffs are chosen
at analysis time in Stata from dist_m.

Also emits per-event contamination counts at 2.5km and 5km
(design1_events_5km_info.csv) since the 1km counts understate overlap at
these radii.

Columns: event_id, event_date, sale_catastro, sale_date, dist_m, salesamt,
         is_subunit, sale_is_investor_parcel (vs FULL CRIM+Karibe universe),
         buyer_nonhispanic, seller_nonhispanic (Census-surname proxy),
         flag_nominal_price, flag_junk_date

Output (gitignored, large): data/design1/design1_sale_event_pairs_5km.csv
"""

import csv, math, os, sys
from collections import defaultdict
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from annotate_name_ethnicity import load_dict, classify  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
D1 = os.path.join(REPO, "data", "design1")
DT = os.path.join(REPO, "data", "third_party")
ISLAND = os.path.join(DT, "crim_parcels_island.csv")
EVENTS = os.path.join(D1, "design1_events.csv")
OUT_PAIRS = os.path.join(D1, "design1_sale_event_pairs_5km.csv")
OUT_EVINFO = os.path.join(D1, "design1_events_5km_info.csv")

RADIUS = 5000.0
CELL = 0.0495  # deg; 3x3 neighborhood covers > 5km everywhere in PR


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


def main():
    csv.field_size_limit(10_000_000)

    # investor universe (full: CRIM name-match + Karibe base)
    investor = set()
    for f in ["crim_parcel_enriched.csv", "karibe_parcels_uniquematch_enriched.csv"]:
        for r in csv.DictReader(open(os.path.join(DT, f), newline="", encoding="utf-8")):
            c = (r.get("CATASTRO") or "").strip()
            if c:
                investor.add(c)

    pct_dict = load_dict()
    name_cache = {}

    # events
    events = []
    for r in csv.DictReader(open(EVENTS, newline="", encoding="utf-8")):
        d = parse_date(r["event_date"])
        if d is None:
            continue
        events.append({"id": r["event_id"], "lon": float(r["lon"]), "lat": float(r["lat"]),
                       "date": d, "date_s": r["event_date"],
                       "own": set(r["catastros"].split(";"))})
    print(f"events: {len(events)}")

    # per-event contamination at 2.5/5km (O(n^2) fine at this n)
    with open(OUT_EVINFO, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["event_id", "n_other_events_within_2500m", "n_other_events_within_5000m"])
        for e in events:
            n25 = n50 = 0
            for o in events:
                if o["id"] == e["id"]:
                    continue
                if abs(o["lon"] - e["lon"]) > 0.055 or abs(o["lat"] - e["lat"]) > 0.05:
                    continue
                dm = haversine_m(e["lon"], e["lat"], o["lon"], o["lat"])
                n25 += dm <= 2500
                n50 += dm <= 5000
            w.writerow([e["id"], n25, n50])
    print(f"wrote {OUT_EVINFO}")

    # island sales pool (compact tuples)
    print("loading island snapshot (sales only)...")
    sales, grid = [], defaultdict(list)
    with open(ISLAND, newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if not (r.get("SALESDTTM") or "").strip():
                continue
            try:
                x, y = float(r["INSIDE_X"]), float(r["INSIDE_Y"])
            except (TypeError, ValueError):
                continue
            c = (r.get("CATASTRO") or "").strip()
            parts = c.split("-")
            subu = "True" if (len(parts) >= 5 and parts[-1] != "000") else "False"
            sales.append((c, x, y, r.get("SALESDATE", ""), r.get("SALESAMT", ""),
                          subu, r.get("BYERNAME", ""), r.get("SELLERNAME", "")))
            grid[(int(x / CELL), int(y / CELL))].append(len(sales) - 1)
    print(f"  sales with coords: {len(sales):,}")

    header = ["event_id", "event_date", "sale_catastro", "sale_date", "dist_m",
              "salesamt", "is_subunit", "sale_is_investor_parcel",
              "buyer_nonhispanic", "seller_nonhispanic",
              "flag_nominal_price", "flag_junk_date"]
    n_pairs = 0
    with open(OUT_PAIRS, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(header)
        for i, e in enumerate(events, 1):
            cx, cy = int(e["lon"] / CELL), int(e["lat"] / CELL)
            for gx in (cx - 1, cx, cx + 1):
                for gy in (cy - 1, cy, cy + 1):
                    for idx in grid.get((gx, gy), ()):
                        c, x, y, sdate, samt, subu, buyer, seller = sales[idx]
                        if c in e["own"]:
                            continue
                        dm = haversine_m(e["lon"], e["lat"], x, y)
                        if dm > RADIUS:
                            continue
                        sd = parse_date(sdate)
                        try:
                            amt = float(samt)
                        except (TypeError, ValueError):
                            amt = None
                        _, bflag, _ = classify(buyer, pct_dict, name_cache)
                        _, sflag, _ = classify(seller, pct_dict, name_cache)
                        w.writerow([
                            e["id"], e["date_s"], c, sdate, round(dm, 1), samt, subu,
                            "True" if c in investor else "False",
                            bflag, sflag,
                            "True" if (amt is not None and amt < 10000) else "False",
                            "True" if sd is None else "False",
                        ])
                        n_pairs += 1
            if i % 100 == 0 or i == len(events):
                print(f"  {i}/{len(events)} events | pairs {n_pairs:,}")
    print(f"\nDONE. pairs: {n_pairs:,}")
    print(f"  output: {OUT_PAIRS}")


if __name__ == "__main__":
    main()
