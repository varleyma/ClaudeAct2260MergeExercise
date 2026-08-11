"""
Per-municipio program footprint: the island-level 10-11% exercise, repeated
for the largest treated municipios.

For each municipio m:
  uplift(m)  = ring-implied uplift over m's stock (parcel-level beta(d) x
               assessed value x band market/assessed ratio -- Layer 1 method)
             + concentration excess from m's 5+ purchase tracts
               (D2 dose uplift minus ring-implied, from design2_aggregation.csv)
  boom(m)    = m's market stock value x (1 - 1/(1+g_m)), where g_m is the
               municipio's transaction-weighted mean-price growth 2019 -> 2024
               from the Red Atlas tract panel
  footprint(m) = uplift(m) / boom(m)

Output: output/design2/design2_muni_footprint.csv (all municipios) + printed
summary for the top treated ones.
"""

import csv, math, os
from collections import defaultdict
from datetime import datetime

import numpy as np

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
ISLAND = os.path.join(REPO, "data", "third_party", "crim_parcels_island.csv")
EVENTS = os.path.join(REPO, "data", "design1", "design1_events.csv")
DT = os.path.join(REPO, "data", "third_party")
D2AGG = os.path.join(REPO, "output", "design2", "design2_aggregation.csv")
REDATLAS = r"C:\Users\mva284\Dropbox\Ley60PR\data\clean\monthly_data_red_atlas.csv"
OUT = os.path.join(REPO, "output", "design2", "design2_muni_footprint.csv")

BANDS = [250, 500, 1000, 1500, 1750, 2500]
BETA_CENTRAL = np.array([0.077, 0.105, 0.043, 0.027, 0.027, 0.031, 0.0])
RATIO_BAND = None  # computed below
CELL = 0.025
MLAT = 110540.0

# tract fips -> municipio name (from the events file, which carries both)
FOCUS = ["San Juan", "Dorado", "Humacao", "Carolina", "R\u00edo Grande",
         "Rinc\u00f3n", "Guaynabo"]


def norm_muni(s):
    return (s or "").strip()


def main():
    csv.field_size_limit(10_000_000)

    # events + fips->muni map
    ev_xy = []
    fips_muni = {}
    for r in csv.DictReader(open(EVENTS, newline="", encoding="utf-8")):
        try:
            d = datetime.strptime(r["event_date"], "%Y-%m-%d")
        except ValueError:
            continue
        if d.year < 2012:
            continue
        ev_xy.append((float(r["lon"]), float(r["lat"])))
        tg = (r.get("tract_geoid") or "").strip()
        if len(tg) == 11:
            fips_muni[tg[:5]] = norm_muni(r.get("municipio"))
    ev = np.array(ev_xy)
    egrid = defaultdict(list)
    for i, (x, y) in enumerate(ev):
        egrid[(int(x / CELL), int(y / CELL))].append(i)

    investor = set()
    for f in ["crim_parcel_enriched.csv", "karibe_parcels_uniquematch_enriched.csv"]:
        for r in csv.DictReader(open(os.path.join(DT, f), newline="", encoding="utf-8")):
            c = (r.get("CATASTRO") or "").strip()
            if c:
                investor.add(c)

    # ---- pass 1: stock parcels with muni, band, value, recent ratio ----
    P, V, MU, RT = [], [], [], []
    with open(ISLAND, newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            c = (r.get("CATASTRO") or "").strip()
            try:
                x, y = float(r["INSIDE_X"]), float(r["INSIDE_Y"])
                stru = float(r.get("STRUCTURE") or 0)
                tv = float(r.get("TOTALVAL") or 0)
            except (TypeError, ValueError):
                continue
            if stru <= 0 or c in investor:
                continue
            rt = float("nan")
            sd = r.get("SALESDATE") or ""
            try:
                amt = float(r.get("SALESAMT") or 0)
                if sd and int(sd[:4]) >= 2019 and amt > 10000 and tv > 0:
                    rt = amt / tv
            except ValueError:
                pass
            P.append((x, y)); V.append(max(tv, 0.0))
            MU.append(norm_muni(r.get("MUNICIPIO"))); RT.append(rt)
    P = np.array(P); V = np.array(V)
    print(f"stock parcels: {len(P):,}")

    # distances (vectorized per grid block)
    dmin = np.full(len(P), np.inf)
    cells = (P / CELL).astype(int)
    order = np.lexsort((cells[:, 1], cells[:, 0]))
    i0 = 0
    while i0 < len(order):
        i1 = i0
        c0 = tuple(cells[order[i0]])
        while i1 < len(order) and tuple(cells[order[i1]]) == c0:
            i1 += 1
        idx = order[i0:i1]
        cand = []
        for gx in (c0[0]-1, c0[0], c0[0]+1):
            for gy in (c0[1]-1, c0[1], c0[1]+1):
                cand.extend(egrid.get((gx, gy), ()))
        if cand:
            E = ev[cand]
            coslat = math.cos(math.radians(P[idx, 1].mean()))
            dx = (P[idx, None, 0] - E[None, :, 0]) * MLAT * coslat
            dy = (P[idx, None, 1] - E[None, :, 1]) * MLAT
            dmin[idx] = np.sqrt(dx*dx + dy*dy).min(axis=1)
        i0 = i1
    bins = np.digitize(dmin, BANDS)

    # band ratios (Layer-1 convention)
    band_r = []
    for b in range(7):
        vals = [RT[i] for i in range(len(RT)) if bins[i] == b and not math.isnan(RT[i])]
        band_r.append(np.median(vals))
    band_r = np.array(band_r)
    g = np.exp(BETA_CENTRAL) - 1

    vmkt = V * band_r[bins]
    uplift_ring = vmkt * g[bins]

    muni_stock = defaultdict(float)
    muni_ring = defaultdict(float)
    for m, vm, ur in zip(MU, vmkt, uplift_ring):
        muni_stock[m] += vm
        muni_ring[m] += ur

    # ---- concentration excess per muni (5+ tracts, from D2 aggregation) ----
    # also: tract-design-only uplift (dose-specific D2 effect x tract stock,
    # summed over ALL treated tracts) for the design-by-design footprint columns
    muni_conc = defaultdict(float)
    muni_d2 = defaultdict(float)
    for r in csv.DictReader(open(D2AGG, newline="", encoding="utf-8")):
        m = fips_muni.get(r["tract_geoid"][:5], "")
        muni_d2[m] += float(r["uplift_d2_dose"])
        if r["group"] != "hi5":
            continue
        muni_conc[m] += float(r["uplift_d2_dose"]) - float(r["uplift_ring_central"])

    # ---- muni price growth 2019 -> 2024 from the REPEAT-SALES index ----
    # (cumulative log index, base 2000; growth = exp(v2024 - v2019) - 1)
    HPI = (r"C:\Users\mva284\Dropbox\Ley60PR\data\raw\data v2\data v2\year"
           r"\not_inflated\Base=2000&Freq=year&geoDivision=city&inflated=False.csv")
    hpi = defaultdict(dict)
    for r in csv.DictReader(open(HPI, newline="", encoding="utf-8")):
        try:
            hpi[r["geoCityId"].strip()][r["year"][:4]] = float(r["repSalesPerCity"])
        except ValueError:
            continue
    # muni name -> fips via the events-derived map (invert)
    muni_fips = {}
    for f5, m in fips_muni.items():
        muni_fips[m] = f5
    growth = {}
    for m in muni_stock:
        f5 = muni_fips.get(m, "")
        s = hpi.get(f5, {})
        if "2019" in s and "2024" in s:
            growth[m] = math.exp(s["2024"] - s["2019"]) - 1
        else:
            growth[m] = float("nan")

    # ---- assemble ----
    rows = []
    for m in sorted(muni_stock, key=lambda x: -(muni_ring[x] + muni_conc[x])):
        if not m:
            continue
        st = muni_stock[m]
        up = muni_ring[m] + muni_conc[m]
        gm = growth.get(m, float("nan"))
        boom = st * (1 - 1/(1+gm)) if gm and not math.isnan(gm) and gm > -0.9 else float("nan")
        okboom = boom and not math.isnan(boom)
        rows.append({"municipio": m, "stock_B": st/1e9, "uplift_ring_B": muni_ring[m]/1e9,
                     "uplift_conc_B": muni_conc[m]/1e9, "uplift_d2_B": muni_d2[m]/1e9,
                     "uplift_total_B": up/1e9,
                     "uplift_pct_of_stock": 100*up/st if st else float("nan"),
                     "growth_2019_2024_pct": 100*gm if not math.isnan(gm) else float("nan"),
                     "boom_B": boom/1e9 if not math.isnan(boom) else float("nan"),
                     "footprint_pct_of_boom": 100*up/boom if okboom else float("nan"),
                     "footprint_ring_pct_of_boom": 100*muni_ring[m]/boom if okboom else float("nan"),
                     "footprint_d2_pct_of_boom": 100*muni_d2[m]/boom if okboom else float("nan")})

    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        for r in rows:
            w.writerow({k: (round(v, 3) if isinstance(v, float) else v) for k, v in r.items()})

    print(f"\n{'municipio':>12} | {'stock $B':>8} | {'uplift $B':>9} | {'% stock':>7} | {'growth19-24':>11} | {'boom $B':>7} | {'% of boom':>9} | {'ring only':>9} | {'tract DiD':>9}")
    for r in rows:
        if r["municipio"] in FOCUS:
            print(f"{r['municipio']:>12} | {r['stock_B']:>8.1f} | {r['uplift_total_B']:>9.2f} | "
                  f"{r['uplift_pct_of_stock']:>6.1f}% | {r['growth_2019_2024_pct']:>10.1f}% | "
                  f"{r['boom_B']:>7.1f} | {r['footprint_pct_of_boom']:>8.1f}% | "
                  f"{r['footprint_ring_pct_of_boom']:>8.1f}% | {r['footprint_d2_pct_of_boom']:>8.1f}%")
    print(f"\ntable (all municipios): {OUT}")


if __name__ == "__main__":
    main()
