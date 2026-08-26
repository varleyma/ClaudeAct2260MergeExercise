"""
Figure data for the entity-buyer exhibits (upper bound on institutional /
"hedge fund" presence):

  fig 1: entity share of purchases by year (strict LLC/Corp/LP and broad)
  fig 2: purchases by entities at MULTI-ENTITY mailing addresses (the
         one-LLC-per-property signature: >=2 / >=3 distinct entity buyer
         names sharing one normalized mailing address), banks/coops excluded

Output: output/crim_entities/entity_fig_year.csv with
  year, n_total, n_core, n_broad, n_clust2, n_clust3
(counts of >$10k sales; last-sale-only snapshot -- see figure notes)
"""

import csv, os, re
from collections import defaultdict

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
ISLAND = os.path.join(REPO, "data", "third_party", "crim_parcels_island.csv")
OUT = os.path.join(REPO, "output", "crim_entities")

CORP_PAT = re.compile(
    r"\b(LLC|L L C|INC|INCORPORATED|CORP|CORPORATION|LP|L P|LLP|LTD|"
    r"HOLDINGS?|TRUST|CAPITAL|PROPERTIES|INVESTMENTS?|INVERSIONES|"
    r"DEVELOPMENT|DESARROLLO|REALTY|VENTURES?|PARTNERS|GROUP|GRUPO|"
    r"S E|SE CORP|CRL|COOP|COOPERATIVA|BANK|BANCO|ASSOCIATES|ASOCIADOS)\b")
CORE_PAT = re.compile(
    r"\b(LLC|L L C|INC|INCORPORATED|CORP|CORPORATION|LP|L P|LLP|LTD)\b")
BANK_PAT = re.compile(
    r"\b(BANK|BANCO|COOP|COOPERATIVA|CREDIT UNION|FIRSTBANK|SCOTIABANK|"
    r"DORAL|ORIENTAL|SANTANDER|FANNIE|FREDDIE|FHA|HUD|MORTGAGE)\b")


def norm(s):
    s = (s or "").upper()
    s = re.sub(r"[^A-Z0-9 ]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def main():
    csv.field_size_limit(10_000_000)
    n_total = defaultdict(int)
    n_core = defaultdict(int)
    n_broad = defaultdict(int)
    ent_rows = []                      # (year, buyer, addr) non-bank entities
    addr_ents = defaultdict(set)

    with open(ISLAND, newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            sd = (r.get("SALESDATE") or "").strip()
            try:
                amt = float(r.get("SALESAMT") or 0)
                y = int(sd[:4])
            except (ValueError, TypeError):
                continue
            if y < 2000 or y > 2026 or amt <= 10000:
                continue
            buyer = norm(r.get("BYERNAME"))
            if not buyer:
                continue
            n_total[y] += 1
            core = bool(CORE_PAT.search(buyer))
            broad = core or bool(CORP_PAT.search(buyer))
            if core:
                n_core[y] += 1
            if broad:
                n_broad[y] += 1
            if broad and not BANK_PAT.search(buyer):
                addr = norm(r.get("DIRECCION_POSTAL"))
                if len(addr) >= 10:
                    ent_rows.append((y, buyer, addr))
                    addr_ents[addr].add(buyer)

    clust2 = {a for a, es in addr_ents.items() if len(es) >= 2}
    clust3 = {a for a, es in addr_ents.items() if len(es) >= 3}
    n_c2, n_c3 = defaultdict(int), defaultdict(int)
    for y, b, a in ent_rows:
        if a in clust2:
            n_c2[y] += 1
        if a in clust3:
            n_c3[y] += 1

    # PORTFOLIO-SCALE buyers: an entity belongs to a portfolio cluster if its
    # NAME bought >=K parcels, or its mailing ADDRESS accumulates >=K parcels
    # across entity buyers (one-LLC-per-property rolls up here). Banks already
    # excluded from ent_rows.
    name_n = defaultdict(int)
    addr_n = defaultdict(int)
    for y, b, a in ent_rows:
        name_n[b] += 1
        addr_n[a] += 1
    n_p10, n_p25 = defaultdict(int), defaultdict(int)
    for y, b, a in ent_rows:
        big10 = name_n[b] >= 10 or addr_n[a] >= 10
        big25 = name_n[b] >= 25 or addr_n[a] >= 25
        if big10:
            n_p10[y] += 1
        if big25:
            n_p25[y] += 1

    with open(os.path.join(OUT, "entity_fig_year.csv"), "w", newline="",
              encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["year", "n_total", "n_core", "n_broad", "n_clust2",
                    "n_clust3", "n_port10", "n_port25"])
        for y in sorted(n_total):
            w.writerow([y, n_total[y], n_core[y], n_broad[y],
                        n_c2.get(y, 0), n_c3.get(y, 0),
                        n_p10.get(y, 0), n_p25.get(y, 0)])
    print(f"addresses with >=2 entities: {len(clust2):,}; >=3: {len(clust3):,}")
    print(f"portfolio names >=10: {sum(1 for v in name_n.values() if v >= 10):,}; "
          f"portfolio addresses >=10: {sum(1 for v in addr_n.values() if v >= 10):,}")
    print("wrote entity_fig_year.csv")


if __name__ == "__main__":
    main()
