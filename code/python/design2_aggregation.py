"""
Design 2 aggregation: tract-DiD effects capitalized over treated tracts' stock,
compared with the ring-implied aggregation over the SAME tract sets.

Per treated tract t:
    V_mkt(t) = sum of assessed TOTALVAL over improved non-investor parcels x
               tract median market/assessed ratio (2019+ sales; municipio ->
               island fallback for thin tracts)
    D2 uplift        = V_mkt x (exp(effect_group) - 1),  effects from
                       design2 pooled Post: all +0.0755 / 1-4 +0.0376 / 5+ +0.1831
    Ring-implied     = V_mkt x (exp(pred_central_vw) - 1)  [same for conservative]
Aggregates reported for: all treated tracts, 1-4 group, 5+ group; the D2-minus-
ring gap in the 5+ group is the dollar value of the concentration channel.

Output: output/design2/design2_aggregation.csv + printed summary
"""

import csv, math, os, statistics
from collections import defaultdict

import numpy as np
import geopandas as gpd
from shapely.geometry import Point

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
SP = os.path.join(REPO, "data", "third_party")
ISLAND = os.path.join(REPO, "data", "third_party", "crim_parcels_island.csv")
DT = os.path.join(REPO, "data", "third_party")
D2 = os.path.join(REPO, "data", "design2")
OUT = os.path.join(REPO, "output", "design2", "design2_aggregation.csv")

E_ALL, SE_ALL = 0.0755, 0.0181
E_LO,  SE_LO  = 0.0376, 0.0212
E_HI,  SE_HI  = 0.1831, 0.0288


def main():
    csv.field_size_limit(10_000_000)

    investor = set()
    for f in ["crim_parcel_enriched.csv", "karibe_parcels_uniquematch_enriched.csv"]:
        for r in csv.DictReader(open(os.path.join(DT, f), newline="", encoding="utf-8")):
            c = (r.get("CATASTRO") or "").strip()
            if c:
                investor.add(c)

    # ---- island stock parcels: coords, assessed value, recent-sale ratio ----
    lons, lats, tvs, rts = [], [], [], []
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
            lons.append(x); lats.append(y); tvs.append(max(tv, 0.0)); rts.append(rt)
    print(f"stock parcels: {len(lons):,}")

    # ---- tract join ----
    tracts = gpd.read_file(os.path.join(SP, "tracts72")).to_crs(4326)[["GEOID", "geometry"]]
    gdf = gpd.GeoDataFrame({"i": np.arange(len(lons))},
                           geometry=[Point(x, y) for x, y in zip(lons, lats)], crs=4326)
    j = gpd.sjoin(gdf, tracts, how="left", predicate="within")
    j = j[~j.index.duplicated(keep="first")]
    geoid = np.full(len(lons), "", dtype=object)
    geoid[j["i"].values] = j["GEOID"].fillna("").values

    sumV = defaultdict(float)
    tr_ratios = defaultdict(list)
    for g, v, rt in zip(geoid, tvs, rts):
        if not g:
            continue
        sumV[g] += v
        if not math.isnan(rt):
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

    # ---- treatment + ring predictions ----
    trt = {r["tract_geoid"]: int(r["n_events"])
           for r in csv.DictReader(open(os.path.join(D2, "design2_tract_treatment.csv"),
                                        newline="", encoding="utf-8"))}
    pred = {r["tract_geoid"]: (float(r["pred_central_vw"] or 0), float(r["pred_conserv_vw"] or 0))
            for r in csv.DictReader(open(os.path.join(D2, "design2_ring_prediction.csv"),
                                         newline="", encoding="utf-8"))}

    rows = []
    for g, ne in trt.items():
        if g not in sumV:
            continue
        vmkt = sumV[g] * ratio(g)
        grp = "hi5" if ne >= 5 else "lo14"
        e_d2 = E_HI if ne >= 5 else E_LO
        pc, pk = pred.get(g, (0.0, 0.0))
        rows.append({
            "tract_geoid": g, "n_events": ne, "group": grp,
            "V_assessed": sumV[g], "ratio": ratio(g), "V_market": vmkt,
            "uplift_d2_dose": vmkt * (math.exp(e_d2) - 1),
            "uplift_d2_uniform": vmkt * (math.exp(E_ALL) - 1),
            "uplift_ring_central": vmkt * (math.exp(pc) - 1),
            "uplift_ring_conserv": vmkt * (math.exp(pk) - 1),
        })

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    def agg(sel):
        s = [r for r in rows if sel(r)]
        return (len(s), sum(r["V_market"] for r in s),
                sum(r["uplift_d2_dose"] for r in s),
                sum(r["uplift_d2_uniform"] for r in s),
                sum(r["uplift_ring_central"] for r in s),
                sum(r["uplift_ring_conserv"] for r in s))

    B = 1e9
    for name, sel in [("ALL TREATED TRACTS", lambda r: True),
                      ("1-4 PURCHASES", lambda r: r["group"] == "lo14"),
                      ("5+ PURCHASES", lambda r: r["group"] == "hi5")]:
        n, vm, d2d, d2u, rc, rk = agg(sel)
        print(f"\n== {name} (n={n}, market stock ${vm/B:.1f}B) ==")
        print(f"  D2 uplift, dose-specific: ${d2d/B:.2f}B")
        print(f"  D2 uplift, uniform +7.55: ${d2u/B:.2f}B")
        print(f"  ring-implied (central):   ${rc/B:.2f}B")
        print(f"  ring-implied (conserv):   ${rk/B:.2f}B")
        print(f"  D2(dose) minus ring(central) gap: ${(d2d-rc)/B:.2f}B")
    print(f"\ntable: {OUT}")


if __name__ == "__main__":
    main()
