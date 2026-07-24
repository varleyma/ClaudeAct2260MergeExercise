"""
Layer 1 aggregation: integrate the estimated distance gradient over the
exposure distribution of Puerto Rico's housing stock.

For every improved, non-investor parcel in the island snapshot, compute the
distance to the nearest dated decree-era event; bucket into the estimation
bands; combine with two effect profiles (central = detrended, conservative =
near-control headline) to produce:
  - share of stock affected (count- and assessed-value-weighted)
  - average effect on the affected stock
  - island-wide average effect
  - dollar uplift using band-specific market/assessed ratios from recent sales

See chat/write-up for the formal statement. All aggregates are LOWER BOUNDS:
exposure uses identified (unique-match) events only.

Output: output/design1/layer1_exposure.csv (band table) + printed summary
"""

import csv, math, os
from collections import defaultdict
from datetime import datetime

import numpy as np

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
ISLAND = os.path.join(REPO, "data", "third_party", "crim_parcels_island.csv")
EVENTS = os.path.join(REPO, "data", "design1", "design1_events.csv")
DT = os.path.join(REPO, "data", "third_party")
OUT = os.path.join(REPO, "output", "design1", "layer1_exposure.csv")

# bands (upper edges, meters) and effect profiles (log points)
BANDS = [250, 500, 1000, 1500, 1750, 2500]           # then ">2500"
LABELS = ["0_250", "250_500", "500_1000", "1000_1500", "1500_1750", "1750_2500", "gt2500"]
BETA_CENTRAL = [0.077, 0.105, 0.043, 0.027, 0.027, 0.031, 0.0]
BETA_CONSERV = [0.085, 0.099, 0.040, 0.0,   0.0,   0.0,   0.0]

CELL = 0.025          # degrees; 3x3 neighborhood guarantees coverage > 2.5km
MLAT = 110540.0       # meters per degree latitude
RECENT_YEAR = 2019    # sales used for market/assessed ratios


def main():
    csv.field_size_limit(10_000_000)

    # ---- events (dated, decree era) ----
    ev = []
    for r in csv.DictReader(open(EVENTS, newline="", encoding="utf-8")):
        try:
            d = datetime.strptime(r["event_date"], "%Y-%m-%d")
        except ValueError:
            continue
        if d.year < 2012:
            continue
        ev.append((float(r["lon"]), float(r["lat"])))
    ev = np.array(ev)
    print(f"events (decree era): {len(ev)}")
    egrid = defaultdict(list)
    for i, (x, y) in enumerate(ev):
        egrid[(int(x / CELL), int(y / CELL))].append(i)

    # ---- investor parcel set (excluded from the stock) ----
    investor = set()
    for f in ["crim_parcel_enriched.csv", "karibe_parcels_uniquematch_enriched.csv"]:
        for r in csv.DictReader(open(os.path.join(DT, f), newline="", encoding="utf-8")):
            c = (r.get("CATASTRO") or "").strip()
            if c:
                investor.add(c)

    # ---- pass over island snapshot ----
    nb = len(LABELS)
    cnt = np.zeros(nb)                    # improved, non-investor parcels
    val = np.zeros(nb)                    # assessed TOTALVAL sums
    ratios = [[] for _ in range(nb)]      # recent-sale price/assessed ratios
    n_stock = 0
    n_skip_vacant = n_skip_inv = 0

    # buffer parcels by grid cell for vectorized distance computation
    buf = defaultdict(lambda: ([], [], [], []))   # cell -> (lon, lat, totval, ratio_or_nan)

    def flush(cell, lons, lats, tvs, rts):
        cx, cy = cell
        cand = []
        for gx in (cx - 1, cx, cx + 1):
            for gy in (cy - 1, cy, cy + 1):
                cand.extend(egrid.get((gx, gy), ()))
        P = np.array([lons, lats]).T
        if not cand:
            dmin = np.full(len(lons), np.inf)
        else:
            E = ev[cand]
            coslat = math.cos(math.radians(np.mean(lats)))
            dx = (P[:, None, 0] - E[None, :, 0]) * MLAT * coslat
            dy = (P[:, None, 1] - E[None, :, 1]) * MLAT
            dmin = np.sqrt(dx * dx + dy * dy).min(axis=1)
        bins = np.digitize(dmin, BANDS)   # 0..6 (6 = >2500 incl inf)
        for b, tv, rt in zip(bins, tvs, rts):
            cnt[b] += 1
            val[b] += tv
            if not math.isnan(rt):
                ratios[b].append(rt)

    with open(ISLAND, newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            c = (r.get("CATASTRO") or "").strip()
            try:
                x, y = float(r["INSIDE_X"]), float(r["INSIDE_Y"])
                stru = float(r.get("STRUCTURE") or 0)
                tv = float(r.get("TOTALVAL") or 0)
            except (TypeError, ValueError):
                continue
            if stru <= 0:
                n_skip_vacant += 1
                continue
            if c in investor:
                n_skip_inv += 1
                continue
            n_stock += 1
            # recent-sale market/assessed ratio
            rt = float("nan")
            sd = (r.get("SALESDATE") or "")
            try:
                amt = float(r.get("SALESAMT") or 0)
                if sd and int(sd[:4]) >= RECENT_YEAR and amt > 10000 and tv > 0:
                    rt = amt / tv
            except ValueError:
                pass
            cell = (int(x / CELL), int(y / CELL))
            L = buf[cell]
            L[0].append(x); L[1].append(y); L[2].append(tv); L[3].append(rt)

    for cell, (lons, lats, tvs, rts) in buf.items():
        flush(cell, lons, lats, tvs, rts)
    print(f"stock parcels (improved, non-investor): {n_stock:,} "
          f"(excluded: {n_skip_vacant:,} vacant, {n_skip_inv:,} investor)")

    # ---- aggregates ----
    g_c = np.exp(BETA_CENTRAL) - 1
    g_k = np.exp(BETA_CONSERV) - 1
    s = cnt / cnt.sum()
    w = val / val.sum()
    r_med = np.array([np.median(x) if x else np.nan for x in ratios])

    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        wcsv = csv.writer(fh)
        wcsv.writerow(["band", "n_parcels", "share_count", "share_assessed_value",
                       "beta_central", "beta_conservative", "median_mkt_assessed_ratio",
                       "n_ratio_sales"])
        for i, lab in enumerate(LABELS):
            wcsv.writerow([lab, int(cnt[i]), round(s[i], 5), round(w[i], 5),
                           BETA_CENTRAL[i], BETA_CONSERV[i],
                           round(float(r_med[i]), 2) if not math.isnan(r_med[i]) else "",
                           len(ratios[i])])

    aff = slice(0, 6)   # bands <= 2500m
    S_cnt = s[aff].sum()
    S_val = w[aff].sum()
    for name, g in [("CENTRAL (detrended profile)", g_c), ("CONSERVATIVE (near-control)", g_k)]:
        avg_aff_cnt = (s[aff] * g[aff]).sum() / S_cnt
        avg_aff_val = (w[aff] * g[aff]).sum() / S_val
        island = (s * g).sum()
        dv = np.nansum(val * r_med * g)
        print(f"\n== {name} ==")
        print(f"  avg effect on affected stock: {100*avg_aff_cnt:.2f}% (count-wtd), "
              f"{100*avg_aff_val:.2f}% (value-wtd)")
        print(f"  island-wide average effect:   {100*island:.3f}%")
        print(f"  dollar uplift (band ratios):  ${dv/1e9:.2f}B")
    print(f"\naffected share of stock (<=2.5km): {100*S_cnt:.1f}% of parcels, "
          f"{100*S_val:.1f}% of assessed value")
    print(f"table: {OUT}")


if __name__ == "__main__":
    main()
