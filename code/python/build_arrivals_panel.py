"""
Event x ring x year panel of SUBSEQUENT INVESTOR ARRIVALS for the
investor-begets-investor DiD (design1_arrivals_did.do).

An "arrival" at event e, ring b, calendar year t is a DIFFERENT design1
decree-era event (>=2012; events already group same-buyer-same-day parcel
purchases into one dated purchase) by a DIFFERENT buyer whose location falls
in ring b around e and whose event year is t. Rings mirror the headline
near-control price spec (design1_decay_results.do):
    0-250 | 250-500 | 500-1000 | 1000-1500 | control 1500-2000 m.

The panel is the full zero-filled grid: 1,160 events x 5 rings x years
2008-2025, with ring areas (km^2) for per-area rates, the event's year, and
two state-dependence classifications:
  n_prior_1km / pioneer   -- no earlier other-buyer event within 1 km at the
      event date. CAUTION: conditions on the pre-period outcome (pre-window
      arrivals are zero BY CONSTRUCTION) -- descriptive only.
  n_prior_1km_tm4 / pioneer4 -- no other-buyer event within 1 km dated more
      than 4 years (1,461 days) before the event: PREDETERMINED relative to
      the lpdid pre-window (-4..-1), so pre-window arrivals are unconstrained.
      Use THIS one for the DiD splits.

Exclusions: self (same event_id) and same normalized buyer string (an
investor's own later purchases are not "another investor arriving").

Outputs: data/design1/arrivals_panel.csv
         data/design1/design1_events_prior.csv (event_id, n_prior_1km, pioneer)
"""

import csv, math, os
from collections import defaultdict
from datetime import datetime, timedelta

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
EVENTS_SRC = os.path.join(REPO, "data", "design1", "design1_events.csv")
OUT_DIR = os.path.join(REPO, "data", "design1")

BINS = [("0_250", 0.0, 250.0), ("250_500", 250.0, 500.0),
        ("500_1000", 500.0, 1000.0), ("1000_1500", 1000.0, 1500.0),
        ("control", 1500.0, 2000.0)]
RMAX = 2000.0
CELL = 0.022
YEARS = range(2008, 2026)

AREA = {name: round(math.pi * ((hi / 1000) ** 2 - (lo / 1000) ** 2), 4)
        for name, lo, hi in BINS}


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
    events = []
    for r in csv.DictReader(open(EVENTS_SRC, newline="", encoding="utf-8")):
        d = parse_date(r["event_date"])
        if d is None or not (2012 <= d.year <= 2025):
            continue
        events.append({"id": r["event_id"], "lon": float(r["lon"]), "lat": float(r["lat"]),
                       "date": d, "buyer": " ".join((r.get("buyer") or "").upper().split())})
    print(f"decree-era events: {len(events)}")

    grid = defaultdict(list)
    for i, e in enumerate(events):
        grid[(int(e["lon"] / CELL), int(e["lat"] / CELL))].append(i)

    # arrivals[event_id][(bin, year)] = count ; prior-event counts within 1km
    arrivals = defaultdict(lambda: defaultdict(int))
    n_prior = defaultdict(int)
    n_prior_tm4 = defaultdict(int)
    for e in events:
        cutoff_tm4 = e["date"] - timedelta(days=1461)
        cx, cy = int(e["lon"] / CELL), int(e["lat"] / CELL)
        for gx in (cx - 1, cx, cx + 1):
            for gy in (cy - 1, cy, cy + 1):
                for j in grid.get((gx, gy), ()):
                    o = events[j]
                    if o["id"] == e["id"] or o["buyer"] == e["buyer"]:
                        continue
                    dm = haversine_m(e["lon"], e["lat"], o["lon"], o["lat"])
                    if dm > RMAX:
                        continue
                    for name, lo, hi in BINS:
                        if lo < dm <= hi or (dm == 0.0 and lo == 0.0):
                            arrivals[e["id"]][(name, o["date"].year)] += 1
                            break
                    if dm <= 1000.0 and o["date"] < e["date"]:
                        n_prior[e["id"]] += 1
                    if dm <= 1000.0 and o["date"] < cutoff_tm4:
                        n_prior_tm4[e["id"]] += 1

    with open(os.path.join(OUT_DIR, "design1_events_prior.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["event_id", "n_prior_1km", "pioneer",
                                           "n_prior_1km_tm4", "pioneer4"])
        w.writeheader()
        for e in events:
            w.writerow({"event_id": e["id"], "n_prior_1km": n_prior[e["id"]],
                        "pioneer": int(n_prior[e["id"]] == 0),
                        "n_prior_1km_tm4": n_prior_tm4[e["id"]],
                        "pioneer4": int(n_prior_tm4[e["id"]] == 0)})
    n_pio = sum(1 for e in events if n_prior[e["id"]] == 0)
    n_pio4 = sum(1 for e in events if n_prior_tm4[e["id"]] == 0)
    print(f"pioneer (no prior <1km at event date, MECHANICAL pre=0): {n_pio}/{len(events)}")
    print(f"pioneer4 (no event <1km before t-4y, predetermined): {n_pio4}/{len(events)}")

    n_rows = tot = 0
    with open(os.path.join(OUT_DIR, "arrivals_panel.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["event_id", "event_year", "bin", "area_km2",
                                           "year", "arrivals", "n_prior_1km", "pioneer",
                                           "n_prior_1km_tm4", "pioneer4"])
        w.writeheader()
        for e in events:
            for name, lo, hi in BINS:
                for yr in YEARS:
                    a = arrivals[e["id"]].get((name, yr), 0)
                    tot += a
                    n_rows += 1
                    w.writerow({"event_id": e["id"], "event_year": e["date"].year,
                                "bin": name, "area_km2": AREA[name], "year": yr,
                                "arrivals": a, "n_prior_1km": n_prior[e["id"]],
                                "pioneer": int(n_prior[e["id"]] == 0),
                                "n_prior_1km_tm4": n_prior_tm4[e["id"]],
                                "pioneer4": int(n_prior_tm4[e["id"]] == 0)})
    print(f"panel rows: {n_rows:,} | total arrival pairs counted: {tot:,}")
    print("outputs: arrivals_panel.csv, design1_events_prior.csv")


if __name__ == "__main__":
    main()
