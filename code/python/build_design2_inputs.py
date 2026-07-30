"""
Design 2 inputs: tract-level treatment timing/dose + ring-implied predictions.

Outputs (repo data/design2/):
  design2_tract_treatment.csv   one row per 2020 tract with any decree-era
      identified event: first_event_year, n_events, n_events_by_2025
  design2_ring_prediction.csv   one row per tract: the RING-IMPLIED predicted
      tract-level log-price effect = stock-value-weighted mean of beta(d_j)
      over the tract's improved non-investor parcels (central & conservative
      profiles; parcels >2.5km from any event contribute 0). This is what the
      tract DiD estimate SHOULD be if micro-spillovers were the whole story --
      the reconciliation benchmark.

Method: island snapshot parcels spatial-joined to 2020 tracts (TIGER, local),
distance-to-nearest-event as in layer1_aggregate_exposure.py.
"""

import csv, math, os
from collections import defaultdict
from datetime import datetime

import numpy as np
import geopandas as gpd
from shapely.geometry import Point

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
SP = r"C:\Users\mva284\AppData\Local\Temp\claude\C--Users-mva284-Dropbox-ClaudeAct2260MergeExercise\b80c9a74-aa99-4561-adf0-041046ec7be2\scratchpad"
ISLAND = os.path.join(REPO, "data", "third_party", "crim_parcels_island.csv")
EVENTS = os.path.join(REPO, "data", "design1", "design1_events.csv")
DT = os.path.join(REPO, "data", "third_party")
OUTDIR = os.path.join(REPO, "data", "design2")

BANDS = [250, 500, 1000, 1500, 1750, 2500]
BETA_CENTRAL = np.array([0.077, 0.105, 0.043, 0.027, 0.027, 0.031, 0.0])
BETA_CONSERV = np.array([0.085, 0.099, 0.040, 0.0,   0.0,   0.0,   0.0])
CELL = 0.025
MLAT = 110540.0


def main():
    csv.field_size_limit(10_000_000)
    os.makedirs(OUTDIR, exist_ok=True)

    # ---- events: timing + dose per tract, and locations for distances ----
    ev_xy, tract_events = [], defaultdict(list)
    for r in csv.DictReader(open(EVENTS, newline="", encoding="utf-8")):
        try:
            d = datetime.strptime(r["event_date"], "%Y-%m-%d")
        except ValueError:
            continue
        if d.year < 2012:
            continue
        ev_xy.append((float(r["lon"]), float(r["lat"])))
        tract_events[(r.get("tract_geoid") or "").strip()].append(d.year)
    ev = np.array(ev_xy)
    print(f"decree-era events: {len(ev)} in {len(tract_events)} tracts")

    with open(os.path.join(OUTDIR, "design2_tract_treatment.csv"), "w",
              newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["tract_geoid", "first_event_year", "n_events"])
        for t, ys in sorted(tract_events.items()):
            if t:
                w.writerow([t, min(ys), len(ys)])
    print("wrote design2_tract_treatment.csv")

    egrid = defaultdict(list)
    for i, (x, y) in enumerate(ev):
        egrid[(int(x / CELL), int(y / CELL))].append(i)

    # ---- investor parcels excluded from stock ----
    investor = set()
    for f in ["crim_parcel_enriched.csv", "karibe_parcels_uniquematch_enriched.csv"]:
        for r in csv.DictReader(open(os.path.join(DT, f), newline="", encoding="utf-8")):
            c = (r.get("CATASTRO") or "").strip()
            if c:
                investor.add(c)

    # ---- stock parcels: location + assessed value ----
    lons, lats, tvs = [], [], []
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
            lons.append(x); lats.append(y); tvs.append(max(tv, 0.0))
    P = np.array([lons, lats]).T
    V = np.array(tvs)
    print(f"stock parcels: {len(P):,}")

    # ---- distance to nearest event (vectorized per grid block) ----
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
    bins = np.digitize(dmin, BANDS)          # 0..6
    beta_c = BETA_CENTRAL[bins]
    beta_k = BETA_CONSERV[bins]

    # ---- spatial join parcels -> 2020 tracts ----
    print("spatial join to tracts...")
    tracts = gpd.read_file(os.path.join(SP, "tracts72")).to_crs(4326)[["GEOID", "geometry"]]
    gdf = gpd.GeoDataFrame({"i": np.arange(len(P))},
                           geometry=[Point(xy) for xy in P], crs=4326)
    j = gpd.sjoin(gdf, tracts, how="left", predicate="within")
    j = j[~j.index.duplicated(keep="first")]
    geoid = np.full(len(P), "", dtype=object)
    geoid[j["i"].values] = j["GEOID"].fillna("").values

    # ---- aggregate predictions per tract (value- and count-weighted) ----
    agg = defaultdict(lambda: [0.0, 0.0, 0.0, 0, 0.0, 0.0])
    # [sumV, sumV*bc, sumV*bk, n, sum_bc, sum_bk]
    for g, v, bc, bk in zip(geoid, V, beta_c, beta_k):
        if not g:
            continue
        a = agg[g]
        a[0] += v; a[1] += v*bc; a[2] += v*bk
        a[3] += 1; a[4] += bc; a[5] += bk
    with open(os.path.join(OUTDIR, "design2_ring_prediction.csv"), "w",
              newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["tract_geoid", "pred_central_vw", "pred_conserv_vw",
                    "pred_central_cw", "pred_conserv_cw", "n_stock_parcels"])
        for g, a in sorted(agg.items()):
            vw_c = a[1]/a[0] if a[0] > 0 else ""
            vw_k = a[2]/a[0] if a[0] > 0 else ""
            w.writerow([g,
                        round(vw_c, 5) if vw_c != "" else "",
                        round(vw_k, 5) if vw_k != "" else "",
                        round(a[4]/a[3], 5), round(a[5]/a[3], 5), a[3]])
    print(f"wrote design2_ring_prediction.csv ({len(agg)} tracts)")


if __name__ == "__main__":
    main()
