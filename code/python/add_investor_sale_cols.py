"""
Add the nearest investor parcel's own sale info to a nearby-sales CSV.

Joins nearest_investor_catastro -> crim_parcel_enriched.csv[CATASTRO] and appends:
    investor_SALESAMT     nearest investor parcel's sale amount
    investor_SALESDATE    nearest investor parcel's sale date (YYYY-MM-DD)
    investor_SELLERNAME   who sold to the investor
    investor_BYERNAME     buyer of record on the investor parcel

Idempotent: re-running refreshes the columns in place (safe after the full
nearby-sales run finishes, and safe to re-run if the enriched file changes).

Usage:
    add_investor_sale_cols.py <nearby_sales_csv>
"""

import csv, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ENRICHED = os.path.join(ROOT, "data", "third_party", "crim_parcel_enriched.csv")

ADD = ["investor_SALESAMT", "investor_SALESDATE", "investor_SELLERNAME", "investor_BYERNAME"]
SRC = ["SALESAMT", "SALESDATE", "SELLERNAME", "BYERNAME"]


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: add_investor_sale_cols.py <nearby_sales_csv> [<enriched_lookup_csv>]")
    target = sys.argv[1]
    lookup = sys.argv[2] if len(sys.argv) == 3 else ENRICHED

    inv = {}
    with open(lookup, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            c = (row.get("CATASTRO") or "").strip()
            if c:
                inv[c] = {a: row.get(s, "") for a, s in zip(ADD, SRC)}
    print(f"investor lookup: {len(inv)} parcels")

    with open(target, newline="", encoding="utf-8") as fh:
        r = csv.DictReader(fh)
        fields = list(r.fieldnames)
        rows = list(r)

    out_fields = fields + [c for c in ADD if c not in fields]
    matched = 0
    for d in rows:
        info = inv.get((d.get("nearest_investor_catastro") or "").strip())
        if info:
            matched += 1
            d.update(info)
        else:
            for a in ADD:
                d.setdefault(a, "")

    tmp = target + ".tmp"
    with open(tmp, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=out_fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    os.replace(tmp, target)

    with_date = sum(1 for d in rows if d.get("investor_SALESDATE"))
    print(f"annotated {target}")
    print(f"  rows: {len(rows)}  joined to investor parcel: {matched}  with investor sale date: {with_date}")


if __name__ == "__main__":
    main()
