"""
Diagnose the rel==0 blip in the portfolio-purchase tract DiD: list treated
tract-years AT the treatment year with portfolio-cluster purchases, and the
buyer names behind them.

Output: printed listing + output/design2/entity_t0_diagnostic.csv
"""

import csv, os, re
from collections import defaultdict

import numpy as np
import geopandas as gpd
from shapely.geometry import Point

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
ISLAND = os.path.join(REPO, "data", "third_party", "crim_parcels_island.csv")
TRACTS = os.path.join(REPO, "data", "third_party", "tracts72")
D2 = os.path.join(REPO, "data", "design2")

CORP_PAT = re.compile(
    r"\b(LLC|L L C|INC|INCORPORATED|CORP|CORPORATION|LP|L P|LLP|LTD|"
    r"HOLDINGS?|TRUST|CAPITAL|PROPERTIES|INVESTMENTS?|INVERSIONES|"
    r"DEVELOPMENT|DESARROLLO|REALTY|VENTURES?|PARTNERS|GROUP|GRUPO|"
    r"S E|SE CORP|CRL|COOP|COOPERATIVA|BANK|BANCO|ASSOCIATES|ASOCIADOS)\b")
BANK_PAT = re.compile(
    r"\b(BANK|BANCO|COOP|COOPERATIVA|CREDIT UNION|FIRSTBANK|SCOTIABANK|"
    r"DORAL|ORIENTAL|SANTANDER|FANNIE|FREDDIE|FHA|HUD|MORTGAGE)\b")


def norm(s):
    s = (s or "").upper()
    s = re.sub(r"[^A-Z0-9 ]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def main():
    csv.field_size_limit(10_000_000)
    trt = {}
    for r in csv.DictReader(open(os.path.join(D2, "design2_tract_treatment.csv"),
                                 encoding="utf-8")):
        try:
            trt[r["tract_geoid"]] = int(r["first_event_year"])
        except (ValueError, KeyError):
            pass

    rows = []
    name_n = defaultdict(int)
    addr_n = defaultdict(int)
    with open(ISLAND, newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            sd = (r.get("SALESDATE") or "").strip()
            try:
                amt = float(r.get("SALESAMT") or 0)
                y = int(sd[:4])
                x, yy = float(r["INSIDE_X"]), float(r["INSIDE_Y"])
            except (ValueError, TypeError, KeyError):
                continue
            if y < 2000 or y > 2026 or amt <= 10000:
                continue
            buyer = norm(r.get("BYERNAME"))
            if not buyer or not CORP_PAT.search(buyer) or BANK_PAT.search(buyer):
                continue
            addr = norm(r.get("DIRECCION_POSTAL"))
            name_n[buyer] += 1
            if len(addr) >= 10:
                addr_n[addr] += 1
            rows.append((y, x, yy, buyer, addr, amt, (r.get("MUNICIPIO") or "").strip()))

    tracts = gpd.read_file(TRACTS).to_crs(4326)[["GEOID", "geometry"]]
    gdf = gpd.GeoDataFrame({"i": np.arange(len(rows))},
                           geometry=[Point(r[1], r[2]) for r in rows], crs=4326)
    j = gpd.sjoin(gdf, tracts, how="left", predicate="within")
    j = j[~j.index.duplicated(keep="first")]
    geoid = np.full(len(rows), "", dtype=object)
    geoid[j["i"].values] = j["GEOID"].fillna("").values

    t0 = defaultdict(lambda: defaultdict(int))
    for (y, x, yy, buyer, addr, amt, muni), g in zip(rows, geoid):
        if len(g) != 11 or trt.get(g) != y:
            continue
        p10 = name_n[buyer] >= 10 or (addr and addr_n[addr] >= 10)
        if p10:
            t0[(g, y, muni)][buyer] += 1

    out = []
    for (g, y, muni), buyers in t0.items():
        n = sum(buyers.values())
        out.append((n, g, y, muni, buyers))
    out.sort(reverse=True)
    tot = sum(o[0] for o in out)
    print(f"rel==0 portfolio purchases total: {tot}, across {len(out)} tract-years")
    print(f"top-5 tract-years account for {sum(o[0] for o in out[:5])} ({sum(o[0] for o in out[:5])/tot:.0%})")
    with open(os.path.join(REPO, "output", "design2", "entity_t0_diagnostic.csv"),
              "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["tract_geoid", "year", "municipio", "port10_n", "buyers"])
        for n, g, y, muni, buyers in out:
            w.writerow([g, y, muni, n,
                        " | ".join(f"{b} ({k})" for b, k in
                                   sorted(buyers.items(), key=lambda kv: -kv[1])[:5])])
    for n, g, y, muni, buyers in out[:8]:
        tops = ", ".join(f"{b[:45]} x{k}" for b, k in
                         sorted(buyers.items(), key=lambda kv: -kv[1])[:3])
        print(f"  {n:3} | {muni:12} {y} tract {g} | {tops}")


if __name__ == "__main__":
    main()
