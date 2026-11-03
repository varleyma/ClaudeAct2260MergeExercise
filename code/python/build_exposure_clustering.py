"""
Buyer-exposure and investor-clustering statistics for the descriptive section.

Two objects, both computed in one streaming pass over the island-wide CRIM
snapshot plus the design1 event list:

1. BUYER EXPOSURE ("odds an Act 60 investor is already nearby when you move
   in"): for every market purchase (individual non-corporate buyer, parcel not
   investor-owned, price >= $10k, valid date), does at least one design1
   investor event (decree era, >=2012) with event_date STRICTLY BEFORE the
   sale date lie within 250 / 500 / 1000 / 2000 m?  Shares by sale year.

2. INVESTOR CLUSTERING vs LUXURY BENCHMARK: the same prior-investor-nearby
   probability for (a) the investor events themselves (other events only,
   different buyer) and (b) an island-wide "luxury benchmark" of individual
   purchases in the [p25, p95] band of investor purchase amounts (same band
   construction as build_placebo_event_panel.py).  The benchmark answers
   "is this clustering, or just where expensive houses are?".
   NOTE: data/design1/placebo_events.csv is NOT usable here -- those placebos
   are co-located <=250m from real events by construction.
   The luxury shares are reweighted to the investor events' year distribution
   before computing odds ratios (exposure rises mechanically over time).

Known caveats (flag in figure notes): CRIM keeps only the LAST sale per
parcel, so early buyer cohorts are thinner and selected toward parcels not
resold since; the investor universe is name-matched owners of record (LLC
purchases invisible) -- exposure is a lower bound.

Inputs (repo): data/third_party/crim_parcels_island.csv (gitignored, 463MB)
               data/design1/design1_events.csv
               data/cleaned/investor_parcels_high_confidence.csv
Outputs (repo): data/design1/exposure_by_year.csv
                data/design1/exposure_by_year_muni.csv
                data/design1/clustering_summary.csv
                data/design1/clustering_by_year.csv
"""

import csv, math, os, re
from collections import defaultdict
from datetime import datetime

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
ISLAND = os.path.join(REPO, "data", "third_party", "crim_parcels_island.csv")
EVENTS_SRC = os.path.join(REPO, "data", "design1", "design1_events.csv")
INVESTOR_SRC = os.path.join(REPO, "data", "cleaned", "investor_parcels_high_confidence.csv")
OUT_DIR = os.path.join(REPO, "data", "design1")

RADII = (250.0, 500.0, 1000.0, 2000.0)
RMAX = max(RADII)
CELL = 0.022            # deg; 3x3 neighborhood covers >2km at PR latitude
MIN_PRICE = 10_000.0    # same nominal-price cutoff as design1 pair flags
YEARS = range(2012, 2026)

# same individual-buyer screen as build_placebo_event_panel.py
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


class Counter4:
    """n plus exposure numerators at each radius and a 1km count sum."""
    __slots__ = ("n", "hit", "sum_n1000")

    def __init__(self):
        self.n = 0
        self.hit = [0, 0, 0, 0]
        self.sum_n1000 = 0

    def add(self, hits, n1000):
        self.n += 1
        for i, h in enumerate(hits):
            self.hit[i] += h
        self.sum_n1000 += n1000


def main():
    csv.field_size_limit(10_000_000)

    # ---- decree-era events ----
    events = []
    for r in csv.DictReader(open(EVENTS_SRC, newline="", encoding="utf-8")):
        d = parse_date(r["event_date"])
        if d is None or not (2012 <= d.year <= 2025):
            continue
        events.append({"id": r["event_id"], "lon": float(r["lon"]), "lat": float(r["lat"]),
                       "date": d, "buyer": (r.get("buyer") or "").strip().upper(),
                       "amt": fnum(r.get("total_investor_salesamt"))})
    amts = sorted(e["amt"] for e in events if e["amt"])
    p25, p95 = amts[len(amts) // 4], amts[int(len(amts) * 0.95)]
    print(f"decree-era events: {len(events)} | luxury band [p25,p95] = [{p25:,.0f}, {p95:,.0f}]")

    egrid = defaultdict(list)
    for i, e in enumerate(events):
        egrid[(int(e["lon"] / CELL), int(e["lat"] / CELL))].append(i)

    def prior_exposure(lon, lat, when, skip_buyer=None):
        """hits per radius (any event strictly before `when`), count within 1km."""
        hits, n1000 = [0, 0, 0, 0], 0
        cx, cy = int(lon / CELL), int(lat / CELL)
        for gx in (cx - 1, cx, cx + 1):
            for gy in (cy - 1, cy, cy + 1):
                for i in egrid.get((gx, gy), ()):
                    e = events[i]
                    if e["date"] >= when:
                        continue
                    if skip_buyer is not None and e["buyer"] == skip_buyer:
                        continue
                    dm = haversine_m(lon, lat, e["lon"], e["lat"])
                    if dm > RMAX:
                        continue
                    for j, rad in enumerate(RADII):
                        if dm <= rad:
                            hits[j] = 1
                    if dm <= 1000.0:
                        n1000 += 1
        return hits, n1000

    # ---- investor parcel catastros (exclude from the market denominator) ----
    investor_cats = set()
    for r in csv.DictReader(open(INVESTOR_SRC, newline="", encoding="utf-8")):
        c = (r.get("CATASTRO") or "").strip()
        if c:
            investor_cats.add(c)
    for r in csv.DictReader(open(EVENTS_SRC, newline="", encoding="utf-8")):
        for c in re.split(r"[;|,\s]+", r.get("catastros") or ""):
            if c.strip():
                investor_cats.add(c.strip())
    print(f"investor parcel catastros: {len(investor_cats):,}")

    # ---- streaming pass over the island snapshot ----
    market = defaultdict(Counter4)        # year -> Counter4  (individual buyers)
    allsales = defaultdict(Counter4)      # year -> Counter4  (any buyer, non-nominal)
    lux = defaultdict(Counter4)           # year -> Counter4  (luxury benchmark)
    muni = defaultdict(Counter4)          # (muni, year) -> Counter4 (market, 1km focus)

    n_rows = n_used = 0
    with open(ISLAND, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            n_rows += 1
            if n_rows % 200_000 == 0:
                print(f"  {n_rows:,} rows | market sales used {n_used:,}")
            d = parse_date(row.get("SALESDATE"))
            if d is None or not (2012 <= d.year <= 2025):
                continue
            amt = fnum(row.get("SALESAMT"))
            if amt is None or amt < MIN_PRICE:
                continue
            try:
                x, y = float(row["INSIDE_X"]), float(row["INSIDE_Y"])
            except (TypeError, ValueError):
                continue
            cat = (row.get("CATASTRO") or "").strip()
            if cat in investor_cats:
                continue
            hits, n1000 = prior_exposure(x, y, d)
            allsales[d.year].add(hits, n1000)
            buyer = (row.get("BYERNAME") or "").strip().upper()
            if not buyer or CORP_RE.search(buyer):
                continue
            n_used += 1
            market[d.year].add(hits, n1000)
            muni[((row.get("MUNICIPIO") or "").strip(), d.year)].add(hits, n1000)
            if p25 <= amt <= p95:
                lux[d.year].add(hits, n1000)
    print(f"island rows: {n_rows:,} | market purchases 2012-2025: {n_used:,}")

    # ---- investor events' own exposure (other events, other buyers) ----
    inv = defaultdict(Counter4)
    for e in events:
        hits, n1000 = prior_exposure(e["lon"], e["lat"], e["date"], skip_buyer=e["buyer"])
        inv[e["date"].year].add(hits, n1000)

    # ---- write year panels ----
    def share_row(c):
        out = {"n": c.n}
        for j, rad in enumerate(RADII):
            out[f"sh{int(rad)}"] = round(c.hit[j] / c.n, 4) if c.n else ""
        out["mean_n_1000"] = round(c.sum_n1000 / c.n, 3) if c.n else ""
        return out

    with open(os.path.join(OUT_DIR, "exposure_by_year.csv"), "w", newline="", encoding="utf-8") as fh:
        cols = ["year", "group", "n"] + [f"sh{int(r)}" for r in RADII] + ["mean_n_1000"]
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        for grp, table in (("market_individual", market), ("all_buyers", allsales),
                           ("luxury_band", lux), ("investor_events", inv)):
            for yr in YEARS:
                if table[yr].n:
                    w.writerow({"year": yr, "group": grp, **share_row(table[yr])})

    with open(os.path.join(OUT_DIR, "exposure_by_year_muni.csv"), "w", newline="", encoding="utf-8") as fh:
        cols = ["municipio", "year", "n"] + [f"sh{int(r)}" for r in RADII] + ["mean_n_1000"]
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        for (m, yr) in sorted(muni):
            if m and muni[(m, yr)].n:
                w.writerow({"municipio": m, "year": yr, **share_row(muni[(m, yr)])})

    # ---- clustering summary: investor vs luxury, year-reweighted ----
    inv_total = sum(inv[y].n for y in YEARS)
    wts = {y: inv[y].n / inv_total for y in YEARS}
    rows = []
    for j, rad in enumerate(RADII):
        p_inv = sum(inv[y].hit[j] for y in YEARS) / inv_total
        p_lux_adj = sum(wts[y] * (lux[y].hit[j] / lux[y].n) for y in YEARS if lux[y].n)
        lux_tot = sum(lux[y].n for y in YEARS)
        p_lux_raw = sum(lux[y].hit[j] for y in YEARS) / lux_tot
        mkt_tot = sum(market[y].n for y in YEARS)
        p_mkt_raw = sum(market[y].hit[j] for y in YEARS) / mkt_tot
        p_mkt_adj = sum(wts[y] * (market[y].hit[j] / market[y].n) for y in YEARS if market[y].n)
        odds = lambda p: p / (1 - p) if 0 < p < 1 else float("nan")
        rows.append({
            "radius_m": int(rad),
            "p_investor": round(p_inv, 4),
            "p_luxury_yearadj": round(p_lux_adj, 4),
            "p_luxury_raw": round(p_lux_raw, 4),
            "p_market_yearadj": round(p_mkt_adj, 4),
            "p_market_raw": round(p_mkt_raw, 4),
            "ratio_vs_luxury": round(p_inv / p_lux_adj, 2) if p_lux_adj else "",
            "odds_ratio_vs_luxury": round(odds(p_inv) / odds(p_lux_adj), 2) if p_lux_adj else "",
            "n_investor": inv_total, "n_luxury": lux_tot, "n_market": mkt_tot,
        })
    with open(os.path.join(OUT_DIR, "clustering_summary.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    # per-year investor-vs-luxury shares at 500m (for a time-series look)
    with open(os.path.join(OUT_DIR, "clustering_by_year.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["year", "n_inv", "p_inv_500", "n_lux", "p_lux_500"])
        w.writeheader()
        for yr in YEARS:
            if inv[yr].n:
                w.writerow({"year": yr, "n_inv": inv[yr].n,
                            "p_inv_500": round(inv[yr].hit[1] / inv[yr].n, 4),
                            "n_lux": lux[yr].n,
                            "p_lux_500": round(lux[yr].hit[1] / lux[yr].n, 4) if lux[yr].n else ""})

    print("\nclustering summary (prior investor within d at purchase):")
    for r in rows:
        print(f"  {r['radius_m']:>5}m  investor {r['p_investor']:.1%}  "
              f"luxury(adj) {r['p_luxury_yearadj']:.1%}  ratio x{r['ratio_vs_luxury']}  OR {r['odds_ratio_vs_luxury']}")
    print("outputs: exposure_by_year.csv, exposure_by_year_muni.csv, "
          "clustering_summary.csv, clustering_by_year.csv")


if __name__ == "__main__":
    main()
