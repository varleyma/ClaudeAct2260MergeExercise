"""
2010 PRCS (ACS 5-year 2006-2010) tract-level baseline covariates for the
Design-2 tract analyses. All PRE-DETERMINED relative to Act 22 (Jan 2012).

Source: Census ACS 2010 5-year SUMMARY FILES (the API now requires a key;
the FTP summary files do not) -- data/third_party/acs2010_sf_pr/ holds the
PR Tracts_Block_Groups_Only geography (g20105pr.txt) and estimate sequence
files (e20105pr0###000.txt) downloaded from
www2.census.gov/programs-surveys/acs/summary_file/2010/.

Cell addressing per the Sequence_Number_and_Table_Number_Lookup: an e-file
row is FILEID,FILETYPE,STUSAB,CHARITER,SEQUENCE,LOGRECNO,cell1,cell2,...;
table cell k sits at 0-based field [start-1 + k-1]. Geography is fixed
width: SUMLEVEL chars 9-11, LOGRECNO chars 14-20, tract GEOID via
'14000US<11 digits>'.

Controls (shares in [0,1]; dollars as reported):
  med_hh_inc     B19013 (seq 53 start 177)   median household income
  med_value      B25077 (seq 99 start 83)    median home value
  med_rent       B25064 (seq 98 start 54)    median gross rent
  poverty        B17001_002/_001 (seq 44 start 7)
  ba_share       B15002 BA+ over 25+ (seq 40 start 90; cells 15-18, 32-35)
  renter_share   B25003_003/_001 (seq 95 start 11)
  vacancy        B25002_003/_001 (seq 95 start 8)
  seasonal_share B25004_006 over B25002_001 (seq 95 start 41)
  mainland_share B05002_004/_001 (seq 17 start 13)  born in another US state
  pop            B01003_001 (seq 11 start 192)

2010 -> 2020 tracts via the tab20 largest-land-overlap crosswalk,
population-weighted means when several 2010 tracts share a 2020 tract.

Output: data/design2/prcs2010_tract_controls.csv (2020-vintage tract_geoid)
"""

import csv, os, re
from collections import defaultdict

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
SF = os.path.join(REPO, "data", "third_party", "acs2010_sf_pr")
XWALK = os.path.join(REPO, "data", "hmda_raw", "tab20_tract20_tract10_natl.txt")
OUT = os.path.join(REPO, "data", "design2", "prcs2010_tract_controls.csv")

SEQS = ["0011", "0017", "0040", "0044", "0053", "0095", "0098", "0099"]


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


def f(x):
    try:
        v = float(x)
    except (TypeError, ValueError):
        return None
    return None if v < 0 else v


def main():
    # geography: logrecno -> 2010 tract geoid (sumlevel 140 only)
    logrec_geo = {}
    with open(os.path.join(SF, "g20105pr.txt"), encoding="latin-1") as fh:
        for line in fh:
            if line[8:11] != "140":
                continue
            m = re.search(r"14000US(\d{11})", line)
            if m:
                logrec_geo[line[13:20]] = m.group(1)

    # estimate sequences: seq -> logrecno -> field list
    seqdata = {}
    for s in SEQS:
        d = {}
        with open(os.path.join(SF, f"e20105pr{s}000.txt"), encoding="latin-1") as fh:
            for line in fh:
                p = line.rstrip("\n").split(",")
                d[p[5]] = p
        seqdata[s] = d

    def cell(seq, logrec, start, k=1):
        row = seqdata[seq].get(logrec)
        if row is None:
            return None
        i = start - 1 + (k - 1)
        return f(row[i]) if i < len(row) else None

    xw = build_xwalk()
    acc = defaultdict(lambda: defaultdict(float))
    wsum = defaultdict(lambda: defaultdict(float))
    n10 = 0
    for lr, g10 in logrec_geo.items():
        g20 = xw.get(g10, "")
        if len(g20) != 11:
            continue
        n10 += 1
        pop = cell("0011", lr, 192) or 0.0
        w = max(pop, 1.0)

        def rat(a, b):
            return (a / b) if (a is not None and b) else None

        ba_num = sum(cell("0040", lr, 90, k) or 0
                     for k in [15, 16, 17, 18, 32, 33, 34, 35])
        ba_den = cell("0040", lr, 90, 1)
        vals = {
            "med_hh_inc": cell("0053", lr, 177),
            "med_value": cell("0099", lr, 83),
            "med_rent": cell("0098", lr, 54),
            "poverty": rat(cell("0044", lr, 7, 2), cell("0044", lr, 7, 1)),
            "ba_share": (ba_num / ba_den) if ba_den else None,
            "renter_share": rat(cell("0095", lr, 11, 3), cell("0095", lr, 11, 1)),
            "vacancy": rat(cell("0095", lr, 8, 3), cell("0095", lr, 8, 1)),
            "seasonal_share": rat(cell("0095", lr, 41, 6), cell("0095", lr, 8, 1)),
            "mainland_share": rat(cell("0017", lr, 13, 4), cell("0017", lr, 13, 1)),
        }
        for k, v in vals.items():
            if v is not None:
                acc[g20][k] += w * v
                wsum[g20][k] += w
        acc[g20]["pop"] += pop
        wsum[g20]["pop"] += 1

    cols = ["med_hh_inc", "med_value", "med_rent", "poverty", "ba_share",
            "renter_share", "vacancy", "seasonal_share", "mainland_share", "pop"]
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["tract_geoid"] + cols)
        for g in sorted(acc):
            row = [g]
            for c in cols:
                if c == "pop":
                    row.append(round(acc[g]["pop"]))
                elif wsum[g][c] > 0:
                    row.append(round(acc[g][c] / wsum[g][c], 5))
                else:
                    row.append("")
            w.writerow(row)
    print(f"2010 tracts read: {n10} -> 2020 tracts written: {len(acc)}")
    # sanity: island-wide medians of the shares
    import statistics
    for c in ["poverty", "seasonal_share", "mainland_share", "renter_share"]:
        v = [acc[g][c] / wsum[g][c] for g in acc if wsum[g][c] > 0]
        print(f"  {c}: median {statistics.median(v):.3f} over {len(v)} tracts")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
