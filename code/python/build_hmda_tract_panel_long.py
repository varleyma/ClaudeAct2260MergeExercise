"""
LONG HMDA tract-year panel for Puerto Rico, 2012-2024, on a CONSISTENT
population: originated FIRST-LIEN, OWNER-OCCUPIED, 1-4 FAMILY HOME-PURCHASE
loans (the only subset CFPB still serves for the historic years, applied
identically to the 2018+ files).

Sources:
  2012-2017  CFPB historic HMDA per-state files
             hmda_YYYY_pr_first-lien-owner-occupied-1-4-family-records_labels.csv
             (2010-vintage tracts; all rows are originated first-lien OO 1-4fam;
              filter loan_purpose == 1)
  2018-2024  HMDA Data Browser extracts hmda_PR_YYYY.csv (originated only;
             filter loan_purpose 1, occupancy_type 1, lien_status 1,
             total_units 1-4)

Ethnicity: 2012-2017 applicant_ethnicity_name; 2018+ derived_ethnicity.
Hispanic vs Not Hispanic; everything else excluded. Income in $000s.
2010->2020 tracts via the tab20 largest-land-overlap crosswalk (2012-2021
files carry 2010 tracts; 2022+ carry 2020 tracts).

Output: data/design2/hmda_tract_year_long.csv with
  tract_geoid, year, purch_n, purch_v,
  purch_{hisp,nonhisp}_{n,v,inc,incn}
"""

import csv, os
from collections import defaultdict

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
RAW = os.path.join(REPO, "data", "hmda_raw")
XWALK = os.path.join(RAW, "tab20_tract20_tract10_natl.txt")
OUT = os.path.join(REPO, "data", "design2", "hmda_tract_year_long.csv")

YEARS_2010 = set(range(2012, 2022))  # files carrying 2010-vintage tracts


def build_xwalk():
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


def hist_geoid(r):
    """72 + 3-digit county + 6-digit tract from the historic file fields."""
    cty = (r.get("county_code") or "").strip()
    tr = (r.get("census_tract_number") or "").strip()
    if not cty or not tr:
        return ""
    try:
        t = float(tr)
    except ValueError:
        return ""
    return "72" + cty.zfill(3) + f"{round(t * 100):06d}"


def main():
    csv.field_size_limit(10_000_000)
    xw = build_xwalk()
    cells = defaultdict(lambda: defaultdict(float))
    skipped = 0

    def add(tract, y, amt, eth, inc):
        c = cells[(tract, y)]
        c["purch_n"] += 1
        c["purch_v"] += amt
        if eth:
            c[f"purch_{eth}_n"] += 1
            c[f"purch_{eth}_v"] += amt
            if inc is not None:
                c[f"purch_{eth}_inc"] += inc
                c[f"purch_{eth}_incn"] += 1

    # ---- historic 2012-2017 ----
    for y in range(2012, 2018):
        p = os.path.join(RAW, f"hmda_{y}_pr_first-lien-owner-occupied-1-4-family-records_labels.csv")
        for r in csv.DictReader(open(p, newline="", encoding="utf-8", errors="replace")):
            if (r.get("loan_purpose") or "").strip() != "1":
                continue
            g = hist_geoid(r)
            g = xw.get(g, "") if y in YEARS_2010 else g
            if len(g) != 11:
                skipped += 1
                continue
            try:
                amt = float(r.get("loan_amount_000s") or 0) * 1000
            except ValueError:
                amt = 0.0
            en = (r.get("applicant_ethnicity_name") or "").strip()
            eth = ("hisp" if en == "Hispanic or Latino"
                   else "nonhisp" if en == "Not Hispanic or Latino" else None)
            try:
                inc = float(r.get("applicant_income_000s") or "")
            except ValueError:
                inc = None
            add(g, y, amt, eth, inc)

    # ---- modern 2018-2024, same population filter ----
    for y in range(2018, 2025):
        p = os.path.join(RAW, f"hmda_PR_{y}.csv")
        for r in csv.DictReader(open(p, newline="", encoding="utf-8", errors="replace")):
            if (r.get("loan_purpose") or "").strip() != "1":
                continue
            if (r.get("occupancy_type") or "").strip() != "1":
                continue
            if (r.get("lien_status") or "").strip() != "1":
                continue
            if (r.get("total_units") or "").strip() not in ("1", "2", "3", "4"):
                continue
            g = (r.get("census_tract") or "").strip()
            if y in YEARS_2010:
                g = xw.get(g, "")
            if len(g) != 11:
                skipped += 1
                continue
            try:
                amt = float(r.get("loan_amount") or 0)
            except ValueError:
                amt = 0.0
            en = (r.get("derived_ethnicity") or "").strip()
            eth = ("hisp" if en == "Hispanic or Latino"
                   else "nonhisp" if en == "Not Hispanic or Latino" else None)
            try:
                inc = float(r.get("income") or "")
            except ValueError:
                inc = None
            add(g, y, amt, eth, inc)

    cols = ["purch_n", "purch_v",
            "purch_hisp_n", "purch_hisp_v", "purch_hisp_inc", "purch_hisp_incn",
            "purch_nonhisp_n", "purch_nonhisp_v", "purch_nonhisp_inc", "purch_nonhisp_incn"]
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["tract_geoid", "year"] + cols)
        for (tract, y), c in sorted(cells.items()):
            w.writerow([tract, y] + [int(c[k]) if k.endswith("_n") or k.endswith("incn")
                                     else round(c[k]) for k in cols])
    yrs = defaultdict(int)
    for (t, y), c in cells.items():
        yrs[y] += c["purch_n"]
    print("purchases/yr:", dict(sorted(yrs.items())))
    print(f"skipped (no tract): {skipped:,} | wrote {OUT} ({len(cells):,} tract-years)")


if __name__ == "__main__":
    main()
