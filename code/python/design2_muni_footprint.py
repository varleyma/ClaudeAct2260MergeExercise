"""
Per-municipio program footprint, in ONE valuation convention so the table's
columns are exactly consistent with each other.

Convention (matches design2_aggregation.py): every parcel's market value is
assessed TOTALVAL x its tract's median market/assessed ratio (2019+ sales;
municipio -> island fallback for thin tracts). On that common stock:

  ring_total(m)  = sum over m's parcels of vmkt x (exp(beta(band)) - 1)
  ring_hi5(m)    = same, restricted to parcels in 5+-purchase tracts
  d2_total(m)    = sum over parcels in treated tracts of vmkt x (exp(E_grp)-1),
                   E from the tract-DiD dose effects (1-4: +0.0376, 5+: +0.1831)
  d2_hi5(m)      = same, 5+ tracts only
  conc(m)        = d2_hi5 - ring_hi5      (concentration excess)
  synth(m)       = ring_total + conc      (ring everywhere, topped up to the
                                           full tract effect inside 5+ tracts)
  boom(m)        = stock(m) x (1 - 1/(1+g_m)), g_m = repeat-sales growth
                   2019 -> 2024 (municipio index)

Identities that hold exactly, row by row:
  synth = ring_total + (d2_hi5 - ring_hi5);  d2_total = d2_hi5 + d2_lo14.

Output: output/design2/design2_muni_footprint.csv (all municipios) + printed
summary for the top treated ones.
"""

import csv, math, os, statistics
from collections import defaultdict
from datetime import datetime

import numpy as np
import geopandas as gpd
from shapely.geometry import Point

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
ISLAND = os.path.join(REPO, "data", "third_party", "crim_parcels_island.csv")
TRACTS = os.path.join(REPO, "data", "third_party", "tracts72")
EVENTS = os.path.join(REPO, "data", "design1", "design1_events.csv")
DT = os.path.join(REPO, "data", "third_party")
D2 = os.path.join(REPO, "data", "design2")
REDATLAS = r"C:\Users\mva284\Dropbox\Ley60PR\data\clean\monthly_data_red_atlas.csv"
OUT = os.path.join(REPO, "output", "design2", "design2_muni_footprint.csv")

BANDS = [250, 500, 1000, 1500, 1750, 2500]
BETA_CENTRAL = np.array([0.077, 0.105, 0.043, 0.027, 0.027, 0.031, 0.0])
E_LO, E_HI = 0.0376, 0.1831   # tract-DiD dose effects (design2 pooled Post)
CELL = 0.025
MLAT = 110540.0

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

    # ---- pass 1: stock parcels with muni, assessed value, recent ratio ----
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

    # ---- tract join (same as design2_aggregation.py) ----
    tracts = gpd.read_file(TRACTS).to_crs(4326)[["GEOID", "geometry"]]
    gdf = gpd.GeoDataFrame({"i": np.arange(len(P))},
                           geometry=[Point(x, y) for x, y in P], crs=4326)
    j = gpd.sjoin(gdf, tracts, how="left", predicate="within")
    j = j[~j.index.duplicated(keep="first")]
    geoid = np.full(len(P), "", dtype=object)
    geoid[j["i"].values] = j["GEOID"].fillna("").values

    # ---- distances to nearest event (vectorized per grid block) ----
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

    # ---- market/assessed ratios: tract median -> muni -> island fallback ----
    tr_ratios = defaultdict(list)
    for g, rt in zip(geoid, RT):
        if g and not math.isnan(rt):
            tr_ratios[g].append(rt)
    island_ratio = statistics.median([x for v in tr_ratios.values() for x in v])
    muni_ratios = defaultdict(list)
    for g, v in tr_ratios.items():
        muni_ratios[g[:5]].extend(v)

    def ratio(g):
        if len(tr_ratios.get(g, [])) >= 5:
            return statistics.median(tr_ratios[g])
        if len(muni_ratios.get(g[:5], [])) >= 5:
            return statistics.median(muni_ratios[g[:5]])
        return island_ratio

    # ---- treated-tract dose groups ----
    n_ev = {r["tract_geoid"]: int(r["n_events"])
            for r in csv.DictReader(open(os.path.join(D2, "design2_tract_treatment.csv"),
                                         newline="", encoding="utf-8"))}

    # ---- accumulate per municipio, one valuation convention throughout ----
    g_band = np.exp(BETA_CENTRAL) - 1
    muni_stock = defaultdict(float)
    muni_ring = defaultdict(float)
    muni_ring_hi5 = defaultdict(float)
    muni_d2 = defaultdict(float)
    muni_d2_hi5 = defaultdict(float)
    for m, gid, v, b in zip(MU, geoid, V, bins):
        vmkt = v * ratio(gid)
        muni_stock[m] += vmkt
        ur = vmkt * g_band[b]
        muni_ring[m] += ur
        ne = n_ev.get(gid, 0)
        if ne >= 1:
            e = E_HI if ne >= 5 else E_LO
            ud = vmkt * (math.exp(e) - 1)
            muni_d2[m] += ud
            if ne >= 5:
                muni_d2_hi5[m] += ud
                muni_ring_hi5[m] += ur

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
    for m in sorted(muni_stock, key=lambda x: -(muni_ring[x] + muni_d2_hi5[x] - muni_ring_hi5[x])):
        if not m:
            continue
        st = muni_stock[m]
        conc = muni_d2_hi5[m] - muni_ring_hi5[m]
        up = muni_ring[m] + conc
        gm = growth.get(m, float("nan"))
        boom = st * (1 - 1/(1+gm)) if gm and not math.isnan(gm) and gm > -0.9 else float("nan")
        okboom = boom and not math.isnan(boom)
        def sh(x):
            return 100*x/boom if okboom else float("nan")
        rows.append({"municipio": m, "stock_B": st/1e9,
                     "uplift_ring_B": muni_ring[m]/1e9,
                     "uplift_ring_hi5_B": muni_ring_hi5[m]/1e9,
                     "uplift_d2_B": muni_d2[m]/1e9,
                     "uplift_d2_hi5_B": muni_d2_hi5[m]/1e9,
                     "uplift_conc_B": conc/1e9,
                     "uplift_synth_B": up/1e9,
                     "uplift_pct_of_stock": 100*up/st if st else float("nan"),
                     "growth_2019_2024_pct": 100*gm if not math.isnan(gm) else float("nan"),
                     "boom_B": boom/1e9 if okboom else float("nan"),
                     "share_ring_pct": sh(muni_ring[m]),
                     "share_ring_hi5_pct": sh(muni_ring_hi5[m]),
                     "share_d2_pct": sh(muni_d2[m]),
                     "share_d2_hi5_pct": sh(muni_d2_hi5[m]),
                     "share_synth_pct": sh(up),
                     "share_conc_pct": sh(conc)})

    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        for r in rows:
            w.writerow({k: (round(v, 3) if isinstance(v, float) else v) for k, v in r.items()})

    print(f"\n{'municipio':>12} | {'growth':>7} | {'boom $B':>7} | {'synth $B':>8} | "
          f"{'ring':>5} {'ring5+':>6} | {'d2':>5} {'d25+':>5} | {'synth':>5} {'conc':>5}")
    for r in rows:
        if r["municipio"] in FOCUS:
            print(f"{r['municipio']:>12} | {r['growth_2019_2024_pct']:>6.1f}% | {r['boom_B']:>7.1f} | "
                  f"{r['uplift_synth_B']:>8.2f} | {r['share_ring_pct']:>4.1f}% {r['share_ring_hi5_pct']:>5.1f}% | "
                  f"{r['share_d2_pct']:>4.1f}% {r['share_d2_hi5_pct']:>4.1f}% | "
                  f"{r['share_synth_pct']:>4.1f}% {r['share_conc_pct']:>4.1f}%")
    print(f"\ntable (all municipios): {OUT}")


if __name__ == "__main__":
    main()
