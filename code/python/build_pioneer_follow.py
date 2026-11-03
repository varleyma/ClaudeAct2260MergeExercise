"""
"Once the first investor arrives, how likely is it that others follow?"

Unit-level dataset for design1_pioneer_follow.do: PIONEER investor purchases
vs VIRGIN LUXURY purchases, with subsequent decree-investor arrivals around
each as outcomes.

  TREATED (pioneer): design1 decree-era events (>=2012) with NO other-buyer
      event within 1 km strictly before the event date (naive first-investor
      definition -- pre-arrival history is zero because that is literally the
      state of the world for a first arrival).
  CONTROL (virgin luxury): island-snapshot purchases by individual
      (non-corporate) buyers, price in the investor [p25,p95] band, parcel
      not in the investor universe, valid date >= 2012, and NO decree event
      within 1 km strictly before the sale date. These are high-value
      purchases in equally investor-free micro-areas: the counterfactual
      arrival risk of "an attractive location that just transacted, but to a
      regular buyer".

Outcomes per unit: counts and any-indicators of subsequent OTHER-BUYER decree
events within 250 / 500 / 1000 m in (date, date + k years], k = 1, 2, 3;
obs_yk flags whether horizon k is fully observable (date + k yrs <= 2025-12-31).

Caveats: LLC/unmatched investors are invisible (some "controls" may be
investors -> attenuation); pioneers chose their spots (residual selection on
investor-specific foresight beyond what the luxury match absorbs).

Inputs: data/design1/design1_events.csv, design1_events_prior.csv,
        data/cleaned/investor_parcels_high_confidence.csv,
        data/third_party/crim_parcels_island.csv
Output: data/design1/pioneer_follow_units.csv
"""

import csv, math, os, re
from collections import defaultdict
from datetime import datetime, timedelta

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
EVENTS_SRC = os.path.join(REPO, "data", "design1", "design1_events.csv")
PRIOR_SRC = os.path.join(REPO, "data", "design1", "design1_events_prior.csv")
INVESTOR_SRC = os.path.join(REPO, "data", "cleaned", "investor_parcels_high_confidence.csv")
ISLAND = os.path.join(REPO, "data", "third_party", "crim_parcels_island.csv")
OUT = os.path.join(REPO, "data", "design1", "pioneer_follow_units.csv")

RADII = (250.0, 500.0, 1000.0)
HORIZONS = (1, 2, 3)
CELL = 0.012            # 3x3 covers >1km
MIN_PRICE = 10_000.0
END_OBS = datetime(2025, 12, 31)

CORP_RE = re.compile(
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

    events = []
    for r in csv.DictReader(open(EVENTS_SRC, newline="", encoding="utf-8")):
        d = parse_date(r["event_date"])
        if d is None or not (2012 <= d.year <= 2025):
            continue
        events.append({"id": r["event_id"], "lon": float(r["lon"]), "lat": float(r["lat"]),
                       "date": d, "buyer": " ".join((r.get("buyer") or "").upper().split()),
                       "muni": r.get("municipio", ""),
                       "amt": fnum(r.get("total_investor_salesamt"))})
    amts = sorted(e["amt"] for e in events if e["amt"])
    p25, p95 = amts[len(amts) // 4], amts[int(len(amts) * 0.95)]
    print(f"decree-era events: {len(events)} | luxury band [{p25:,.0f}, {p95:,.0f}]")

    grid = defaultdict(list)
    for i, e in enumerate(events):
        grid[(int(e["lon"] / CELL), int(e["lat"] / CELL))].append(i)

    pioneer_ids = set()
    for r in csv.DictReader(open(PRIOR_SRC, newline="", encoding="utf-8")):
        if r["pioneer"] == "1":
            pioneer_ids.add(r["event_id"])

    investor_cats = set()
    for r in csv.DictReader(open(INVESTOR_SRC, newline="", encoding="utf-8")):
        c = (r.get("CATASTRO") or "").strip()
        if c:
            investor_cats.add(c)
    for r in csv.DictReader(open(EVENTS_SRC, newline="", encoding="utf-8")):
        for c in re.split(r"[;|,\s]+", r.get("catastros") or ""):
            if c.strip():
                investor_cats.add(c.strip())

    def neighborhood(lon, lat):
        cx, cy = int(lon / CELL), int(lat / CELL)
        for gx in (cx - 1, cx, cx + 1):
            for gy in (cy - 1, cy, cy + 1):
                yield from grid.get((gx, gy), ())

    def follow_outcomes(lon, lat, when, skip_buyer):
        """virgin flag + {(radius, horizon): count} of subsequent arrivals."""
        virgin = True
        cnt = defaultdict(int)
        for j in neighborhood(lon, lat):
            o = events[j]
            if skip_buyer is not None and o["buyer"] == skip_buyer:
                continue
            dm = haversine_m(lon, lat, o["lon"], o["lat"])
            if dm > 1000.0:
                continue
            if o["date"] < when:
                virgin = False
                continue
            if o["date"] == when:
                continue
            for k in HORIZONS:
                if o["date"] <= when + timedelta(days=round(k * 365.25)):
                    for rad in RADII:
                        if dm <= rad:
                            cnt[(rad, k)] += 1
        return virgin, cnt

    cols = ["unit_id", "group", "date", "year", "municipio", "salesamt", "lon", "lat"]
    for rad in RADII:
        for k in HORIZONS:
            cols += [f"n_{int(rad)}_y{k}", f"any_{int(rad)}_y{k}"]
    cols += [f"obs_y{k}" for k in HORIZONS]

    n_pio = n_ctl = 0
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()

        def write_unit(uid, grp, when, muni, amt, lon, lat, cnt):
            row = {"unit_id": uid, "group": grp, "date": when.strftime("%Y-%m-%d"),
                   "year": when.year, "municipio": muni, "salesamt": amt,
                   "lon": round(lon, 6), "lat": round(lat, 6)}
            for rad in RADII:
                for k in HORIZONS:
                    c = cnt.get((rad, k), 0)
                    row[f"n_{int(rad)}_y{k}"] = c
                    row[f"any_{int(rad)}_y{k}"] = int(c > 0)
            for k in HORIZONS:
                row[f"obs_y{k}"] = int(when + timedelta(days=round(k * 365.25)) <= END_OBS)
            w.writerow(row)

        # ---- pioneers ----
        for e in events:
            if e["id"] not in pioneer_ids:
                continue
            virgin, cnt = follow_outcomes(e["lon"], e["lat"], e["date"], e["buyer"])
            write_unit(e["id"], 1, e["date"], e["muni"], e["amt"], e["lon"], e["lat"], cnt)
            n_pio += 1

        # ---- virgin luxury controls ----
        n_rows = 0
        with open(ISLAND, newline="", encoding="utf-8") as ih:
            for row in csv.DictReader(ih):
                n_rows += 1
                if n_rows % 300_000 == 0:
                    print(f"  {n_rows:,} island rows | controls {n_ctl:,}")
                d = parse_date(row.get("SALESDATE"))
                if d is None or not (2012 <= d.year <= 2025):
                    continue
                amt = fnum(row.get("SALESAMT"))
                if amt is None or not (max(p25, MIN_PRICE) <= amt <= p95):
                    continue
                cat = (row.get("CATASTRO") or "").strip()
                if cat in investor_cats:
                    continue
                buyer = (row.get("BYERNAME") or "").strip().upper()
                if not buyer or CORP_RE.search(buyer):
                    continue
                try:
                    x, y = float(row["INSIDE_X"]), float(row["INSIDE_Y"])
                except (TypeError, ValueError):
                    continue
                virgin, cnt = follow_outcomes(x, y, d, None)
                if not virgin:
                    continue
                write_unit(f"C{cat}", 0, d, row.get("MUNICIPIO", ""), amt, x, y, cnt)
                n_ctl += 1

    print(f"pioneers: {n_pio} | virgin luxury controls: {n_ctl}")
    print(f"output: {OUT}")


if __name__ == "__main__":
    main()
