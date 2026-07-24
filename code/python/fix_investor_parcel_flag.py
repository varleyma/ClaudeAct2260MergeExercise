"""
Tighten the investor-parcel flag against the FULL matched-investor universe.

The nearby-sales runs computed neighbor_is_investor_parcel against each run's
own base only, so rows originating from the Karibe-base run were checked
against just the 755 Karibe parcels -- a leak that lets low-confidence CRIM
name-matched parcels near Karibe-only sites pass as "market" sales.

This recomputes the flag in place against the union of
    crim_parcel_enriched.csv (26,673 CRIM name-matched parcels)
  + karibe_parcels_uniquematch_enriched.csv (755)
for the analysis-facing files. Idempotent; reports flips.
"""

import csv, os

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
DT = os.path.join(REPO, "data", "third_party")
D1 = os.path.join(REPO, "data", "design1")

TARGETS = [  # (path, key column, flag column)
    (os.path.join(D1, "design1_sale_event_pairs.csv"), "sale_catastro", "sale_is_investor_parcel"),
    (os.path.join(D1, "placebo_sale_event_pairs.csv"), "sale_catastro", "sale_is_investor_parcel"),
    (os.path.join(DT, "nearby_sales_1000m_uniquematch_combined.csv"), "CATASTRO", "neighbor_is_investor_parcel"),
]


def main():
    csv.field_size_limit(10_000_000)
    investor = set()
    for f in ["crim_parcel_enriched.csv", "karibe_parcels_uniquematch_enriched.csv"]:
        for r in csv.DictReader(open(os.path.join(DT, f), newline="", encoding="utf-8")):
            c = (r.get("CATASTRO") or "").strip()
            if c:
                investor.add(c)
    print(f"investor universe: {len(investor):,} parcels")

    for path, key, flag in TARGETS:
        if not os.path.exists(path):
            print(f"[skip] {path}")
            continue
        tmp = path + ".tmp"
        n = flips = 0
        with open(path, newline="", encoding="utf-8") as fin, \
             open(tmp, "w", newline="", encoding="utf-8") as fout:
            r = csv.DictReader(fin)
            w = csv.DictWriter(fout, fieldnames=r.fieldnames, extrasaction="ignore")
            w.writeheader()
            for row in r:
                n += 1
                correct = "True" if (row.get(key) or "").strip() in investor else "False"
                if row.get(flag, "") != correct:
                    flips += 1
                    row[flag] = correct
                w.writerow(row)
        os.replace(tmp, path)
        print(f"{os.path.basename(path)}: {n:,} rows, flag corrected on {flips:,}")


if __name__ == "__main__":
    main()
