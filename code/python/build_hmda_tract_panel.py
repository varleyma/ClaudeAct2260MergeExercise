"""
HMDA tract-year mortgage origination panel for Puerto Rico, 2018-2024.

From loan-level Data Browser extracts (originated loans, action_taken=1),
aggregate to 2020-vintage tract x year:

    purch_oo_n,  purch_oo_v    home purchases, owner-occupied (principal res.)
    purch_nonoo_n, purch_nonoo_v  home purchases, second home / investment
    purch_hisp_*, purch_nonhisp_*  home purchases split by self-reported
                               derived_ethnicity (Hispanic or Latino vs Not;
                               Joint/Not Available excluded): _n count,
                               _v dollar volume, _inc summed borrower income
                               ($000s) over the _incn loans reporting income
    refi_n, refi_v             rate/term refinancings   (loan_purpose 31)
    cashout_n, cashout_v       cash-out refinancings    (loan_purpose 32)
    total_n, total_v           all originated loans

(_n = counts, _v = dollar volume in $; loan_amount is reported in dollars.)

Tract vintage: 2018-2021 files carry 2010 tracts -> mapped to 2020 tracts by
LARGEST LAND OVERLAP from the Census tab20 relationship file (a many-to-one
approximation; PR 2010->2020 changes are modest). 2022+ carry 2020 tracts.

Output: data/design2/hmda_tract_year.csv
"""

import csv, os
from collections import defaultdict

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
RAW = os.path.join(REPO, "data", "hmda_raw")
XWALK = os.path.join(RAW, "tab20_tract20_tract10_natl.txt")
OUT = os.path.join(REPO, "data", "design2", "hmda_tract_year.csv")

YEARS_2010 = {2018, 2019, 2020, 2021}


def build_xwalk():
    """2010 tract -> 2020 tract with the largest land overlap (PR only)."""
    best = {}
    with open(XWALK, newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh, delimiter="|"):
            t10 = (r.get("GEOID_TRACT_10") or "").strip()
            t20 = (r.get("GEOID_TRACT_20") or "").strip()
            if not t10.startswith("72") or not t20:
                continue
            try:
                land = int(r.get("AREALAND_PART") or 0)
            except ValueError:
                land = 0
            if t10 not in best or land > best[t10][1]:
                best[t10] = (t20, land)
    return {k: v[0] for k, v in best.items()}


def main():
    csv.field_size_limit(10_000_000)
    xw = build_xwalk()
    print(f"crosswalk: {len(xw)} PR 2010 tracts mapped")

    cells = defaultdict(lambda: defaultdict(float))
    n_skip_tract = n_rows = 0
    for y in range(2018, 2025):
        path = os.path.join(RAW, f"hmda_PR_{y}.csv")
        with open(path, newline="", encoding="utf-8") as fh:
            for r in csv.DictReader(fh):
                n_rows += 1
                tract = (r.get("census_tract") or "").strip()
                if len(tract) != 11:
                    n_skip_tract += 1
                    continue
                if y in YEARS_2010:
                    tract = xw.get(tract, "")
                    if not tract:
                        n_skip_tract += 1
                        continue
                try:
                    amt = float(r.get("loan_amount") or 0)
                except ValueError:
                    amt = 0.0
                purpose = (r.get("loan_purpose") or "").strip()
                occ = (r.get("occupancy_type") or "").strip()
                c = cells[(tract, y)]
                c["total_n"] += 1
                c["total_v"] += amt
                if purpose == "1":
                    if occ == "1":
                        c["purch_oo_n"] += 1
                        c["purch_oo_v"] += amt
                    else:
                        c["purch_nonoo_n"] += 1
                        c["purch_nonoo_v"] += amt
                    # self-reported borrower ethnicity + income, purchases only
                    eth = (r.get("derived_ethnicity") or "").strip()
                    if eth == "Hispanic or Latino":
                        ek = "hisp"
                    elif eth == "Not Hispanic or Latino":
                        ek = "nonhisp"
                    else:
                        ek = None   # Joint / Not Available / Free Form excluded
                    if ek:
                        c[f"purch_{ek}_n"] += 1
                        c[f"purch_{ek}_v"] += amt
                        try:
                            inc = float(r.get("income") or "")
                            c[f"purch_{ek}_inc"] += inc  # $000s
                            c[f"purch_{ek}_incn"] += 1
                        except ValueError:
                            pass
                elif purpose == "31":
                    c["refi_n"] += 1
                    c["refi_v"] += amt
                elif purpose == "32":
                    c["cashout_n"] += 1
                    c["cashout_v"] += amt
    print(f"loan rows: {n_rows:,} | skipped (no/unmapped tract): {n_skip_tract:,}")

    cols = ["purch_oo_n", "purch_oo_v", "purch_nonoo_n", "purch_nonoo_v",
            "purch_hisp_n", "purch_hisp_v", "purch_hisp_inc", "purch_hisp_incn",
            "purch_nonhisp_n", "purch_nonhisp_v", "purch_nonhisp_inc", "purch_nonhisp_incn",
            "refi_n", "refi_v", "cashout_n", "cashout_v", "total_n", "total_v"]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["tract_geoid", "year"] + cols)
        for (tract, y), c in sorted(cells.items()):
            w.writerow([tract, y] + [int(c[k]) if k.endswith("_n") else round(c[k]) for k in cols])
    print(f"wrote {OUT} ({len(cells):,} tract-years)")


if __name__ == "__main__":
    main()
