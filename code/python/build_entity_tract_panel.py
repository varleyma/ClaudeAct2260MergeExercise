"""
Tract-year panel of ENTITY and PORTFOLIO-SCALE purchases from the CRIM
island snapshot, for the institutional-deployment tract DiD.

Per sale >$10k with a buyer name (2000-2026), classify:
  entity     non-bank corporate-form buyer (LLC/Corp/LP/... ; banks, coops,
             GSEs excluded as foreclosure REO)
  port10/25  entity belonging to a portfolio cluster: same buyer NAME holds
             10+/25+ parcels island-wide, or its owner mailing ADDRESS
             accumulates 10+/25+ parcels across entity names (rolling up
             one-LLC-per-property structures)

Spatial join to 2020 tracts (data/third_party/tracts72).

Output: data/design2/entity_tract_year.csv with
  tract_geoid, year, sales_n, entity_n, port10_n, port25_n
"""

import csv, os, re
from collections import defaultdict

import numpy as np
import geopandas as gpd
from shapely.geometry import Point

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
ISLAND = os.path.join(REPO, "data", "third_party", "crim_parcels_island.csv")
TRACTS = os.path.join(REPO, "data", "third_party", "tracts72")
OUT = os.path.join(REPO, "data", "design2", "entity_tract_year.csv")

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
    all_rows = []      # (year, x, y, is_entity, buyer, addr)
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
            if not buyer:
                continue
            ent = bool(CORP_PAT.search(buyer)) and not BANK_PAT.search(buyer)
            addr = norm(r.get("DIRECCION_POSTAL")) if ent else ""
            if ent:
                name_n[buyer] += 1
                if len(addr) >= 10:
                    addr_n[addr] += 1
            all_rows.append((y, x, yy, ent, buyer if ent else "", addr))

    print(f"sales kept: {len(all_rows):,}")

    tracts = gpd.read_file(TRACTS).to_crs(4326)[["GEOID", "geometry"]]
    gdf = gpd.GeoDataFrame({"i": np.arange(len(all_rows))},
                           geometry=[Point(r[1], r[2]) for r in all_rows], crs=4326)
    j = gpd.sjoin(gdf, tracts, how="left", predicate="within")
    j = j[~j.index.duplicated(keep="first")]
    geoid = np.full(len(all_rows), "", dtype=object)
    geoid[j["i"].values] = j["GEOID"].fillna("").values

    cells = defaultdict(lambda: [0, 0, 0, 0])
    for (y, x, yy, ent, buyer, addr), g in zip(all_rows, geoid):
        if len(g) != 11:
            continue
        c = cells[(g, y)]
        c[0] += 1
        if ent:
            c[1] += 1
            p10 = name_n[buyer] >= 10 or (addr and addr_n[addr] >= 10)
            p25 = name_n[buyer] >= 25 or (addr and addr_n[addr] >= 25)
            if p10:
                c[2] += 1
            if p25:
                c[3] += 1

    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["tract_geoid", "year", "sales_n", "entity_n",
                    "port10_n", "port25_n"])
        for (g, y), c in sorted(cells.items()):
            w.writerow([g, y] + c)
    tot = defaultdict(int)
    for (g, y), c in cells.items():
        tot[y] += c[2]
    print("port10 purchases/yr (2012+):",
          {y: n for y, n in sorted(tot.items()) if y >= 2012})
    print(f"wrote {OUT} ({len(cells):,} tract-years)")


if __name__ == "__main__":
    main()
