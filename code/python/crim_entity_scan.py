"""
Entity-buyer scan of the island CRIM snapshot: how much property is bought
by legal entities (LLC/Corp/LP/Trust/...), when, where, and in what portfolio
structures?

Caveats: CRIM keeps only each parcel's MOST RECENT sale, so this measures
current entity holdings by acquisition year (resold entity purchases are
overwritten). "Hedge fund" is not identifiable from the deed side; this
scan measures entity purchases and portfolio structure (name clusters and
shared mailing addresses), the observable signature of institutional buying.

Outputs (output/crim_entities/):
  entity_year.csv        purchases & $ by year x buyer class
  entity_muni.csv        post-2012 entity purchases by municipio
  portfolios_name.csv    parcels per normalized buyer name (>=5 parcels)
  portfolios_addr.csv    corporate buyers per normalized mailing address
                         (>=5 parcels across >=2 entity names)
  + printed summary
"""

import csv, os, re
from collections import defaultdict

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
ISLAND = os.path.join(REPO, "data", "third_party", "crim_parcels_island.csv")
OUT = os.path.join(REPO, "output", "crim_entities")
os.makedirs(OUT, exist_ok=True)

# corporate-form tokens (PR + US forms). Word-boundary match on normalized name.
CORP_PAT = re.compile(
    r"\b(LLC|L L C|INC|INCORPORATED|CORP|CORPORATION|LP|L P|LLP|LTD|"
    r"HOLDINGS?|TRUST|CAPITAL|PROPERTIES|INVESTMENTS?|INVERSIONES|"
    r"DEVELOPMENT|DESARROLLO|REALTY|VENTURES?|PARTNERS|GROUP|GRUPO|"
    r"S E|SE CORP|CRL|COOP|COOPERATIVA|BANK|BANCO|ASSOCIATES|ASOCIADOS)\b")
# forms that are clearly institutional/entity (narrow set for the headline)
CORE_PAT = re.compile(
    r"\b(LLC|L L C|INC|INCORPORATED|CORP|CORPORATION|LP|L P|LLP|LTD)\b")


def norm(s):
    s = (s or "").upper()
    s = re.sub(r"[^A-Z0-9 ]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def main():
    csv.field_size_limit(10_000_000)
    yr_stats = defaultdict(lambda: defaultdict(float))
    muni_post = defaultdict(lambda: [0, 0.0])
    name_port = defaultdict(lambda: [0, 0.0])
    addr_port = defaultdict(lambda: [0, 0.0, set()])
    n_rows = n_sales = 0

    with open(ISLAND, newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            n_rows += 1
            sd = (r.get("SALESDATE") or "").strip()
            try:
                amt = float(r.get("SALESAMT") or 0)
                y = int(sd[:4])
            except (ValueError, TypeError):
                continue
            if y < 2000 or y > 2026 or amt <= 10000:
                continue
            n_sales += 1
            buyer = norm(r.get("BYERNAME"))
            if not buyer:
                continue
            core = bool(CORE_PAT.search(buyer))
            broad = core or bool(CORP_PAT.search(buyer))
            cls = "core" if core else ("broad" if broad else "person")
            yr_stats[y][cls + "_n"] += 1
            yr_stats[y][cls + "_v"] += amt
            if broad:
                name_port[buyer][0] += 1
                name_port[buyer][1] += amt
                addr = norm(r.get("DIRECCION_POSTAL"))
                if len(addr) >= 10:
                    a = addr_port[addr]
                    a[0] += 1
                    a[1] += amt
                    a[2].add(buyer)
                if y >= 2012:
                    m = (r.get("MUNICIPIO") or "").strip()
                    muni_post[m][0] += 1
                    muni_post[m][1] += amt

    with open(os.path.join(OUT, "entity_year.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["year", "core_n", "core_v", "broad_n", "broad_v",
                    "person_n", "person_v"])
        for y in sorted(yr_stats):
            s = yr_stats[y]
            w.writerow([y, int(s["core_n"]), round(s["core_v"]),
                        int(s["broad_n"]), round(s["broad_v"]),
                        int(s["person_n"]), round(s["person_v"])])

    with open(os.path.join(OUT, "entity_muni.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["municipio", "n", "value"])
        for m, (n, v) in sorted(muni_post.items(), key=lambda kv: -kv[1][1]):
            w.writerow([m, n, round(v)])

    with open(os.path.join(OUT, "portfolios_name.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["buyer", "parcels", "value"])
        for b, (n, v) in sorted(name_port.items(), key=lambda kv: -kv[1][0]):
            if n >= 5:
                w.writerow([b, n, round(v)])

    with open(os.path.join(OUT, "portfolios_addr.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["mail_address", "parcels", "value", "n_entities", "entities"])
        for a, (n, v, ents) in sorted(addr_port.items(), key=lambda kv: -kv[1][0]):
            if n >= 5 and len(ents) >= 2:
                w.writerow([a, n, round(v), len(ents),
                            " | ".join(sorted(ents)[:8])])

    # ---- summary ----
    tot_n = sum(s["core_n"] + s["broad_n"] + s["person_n"] for s in yr_stats.values())
    print(f"parcels scanned: {n_rows:,}; sales >$10k 2000-2026: {n_sales:,}; "
          f"with buyer name: {tot_n:,}")
    print("\nyear | entity(core) n  $M | entity(broad) n  $M | person n | entity share n / $")
    for y in sorted(yr_stats):
        s = yr_stats[y]
        en, ev = s["core_n"] + s["broad_n"], s["core_v"] + s["broad_v"]
        pn, pv = s["person_n"], s["person_v"]
        print(f"{y} | {int(s['core_n']):5,} {s['core_v']/1e6:8.0f} | "
              f"{int(s['broad_n']):5,} {s['broad_v']/1e6:8.0f} | {int(pn):6,} | "
              f"{en/(en+pn):5.1%} / {ev/(ev+pv):5.1%}")
    ports = [(b, n, v) for b, (n, v) in name_port.items()]
    big = [p for p in ports if p[1] >= 10]
    print(f"\nentity buyer names: {len(ports):,}; with >=10 parcels: {len(big):,}")
    print("top 15 by parcels:")
    for b, n, v in sorted(ports, key=lambda p: -p[1])[:15]:
        print(f"  {n:5,}  ${v/1e6:8.1f}M  {b[:60]}")
    print("\ntop 10 shared mailing addresses (>=2 entities):")
    aa = [(a, n, v, ents) for a, (n, v, ents) in addr_port.items() if len(ents) >= 2]
    for a, n, v, ents in sorted(aa, key=lambda p: -p[1])[:10]:
        print(f"  {n:5,} parcels  ${v/1e6:7.1f}M  {len(ents):3} entities  {a[:55]}")


if __name__ == "__main__":
    main()
