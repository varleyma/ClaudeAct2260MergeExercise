"""Pass 1: chunked scan of the Experian header panel (READ-ONLY from Dropbox).

Finds all Puerto Rico zipcodes present (ZIP prefixes 006xx-007xx and 009xx;
008xx is the US Virgin Islands), counts rows/consumers by year, and saves the
set of consumer keys (ctk) ever observed in a PR zip for pass 2.

Outputs (GitHub repo only):
  data/experian/pr_zip_universe.csv      - distinct PR zips w/ row counts, first/last year
  data/experian/pr_zip_year_counts.csv   - PR rows by year
  data/experian/pr_ctks.csv              - ctks ever observed in a PR zip
  data/experian/scan_summary.txt         - headline numbers + data-quality checks
"""
import os
import time
import pandas as pd
from collections import Counter, defaultdict

SRC = r"C:\Users\mva284\Dropbox\ClaudeAct2260MergeExercise\data\raw\header2005_2023_ctk.dta"
OUT = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise\data\experian"
os.makedirs(OUT, exist_ok=True)

CHUNK = 2_000_000

total_rows = 0
bad_zip_rows = 0          # zip_cd not a 3-5 digit string
pr_zip_rows = Counter()   # PR zip -> row count
pr_zip_years = {}         # PR zip -> [min_year, max_year]
pr_year_rows = Counter()  # year -> PR row count
year_rows = Counter()     # year -> all row count
pr_ctks = set()
pr_ctk_year_pairs = 0
zip_len_counts = Counter()
prev_year_max_seen = None
sorted_by_year = True

t0 = time.time()
with pd.read_stata(SRC, columns=["ctk", "year", "zip_cd"], iterator=True) as rdr:
    while True:
        try:
            df = rdr.read(CHUNK)
        except StopIteration:
            break
        if df is None or len(df) == 0:
            break
        n = len(df)
        total_rows += n

        z = df["zip_cd"].str.strip()
        zip_len_counts.update(z.str.len().value_counts().to_dict())
        # normalize: pad to 5 digits in case leading zeros were dropped
        digits = z.str.fullmatch(r"\d{3,5}")
        bad_zip_rows += int((~digits.fillna(False)).sum())
        z5 = z.where(digits.fillna(False)).str.zfill(5)

        yr = df["year"].astype("Int32")
        year_rows.update(yr.value_counts().to_dict())

        is_pr = z5.str.startswith(("006", "007", "009")) & z5.notna()
        if is_pr.any():
            sub = pd.DataFrame({"ctk": df.loc[is_pr, "ctk"],
                                "year": yr[is_pr],
                                "zip": z5[is_pr]})
            pr_zip_rows.update(sub["zip"].value_counts().to_dict())
            for zp, (mn, mx) in sub.groupby("zip")["year"].agg(["min", "max"]).iterrows():
                if zp in pr_zip_years:
                    pr_zip_years[zp][0] = min(pr_zip_years[zp][0], mn)
                    pr_zip_years[zp][1] = max(pr_zip_years[zp][1], mx)
                else:
                    pr_zip_years[zp] = [mn, mx]
            pr_year_rows.update(sub["year"].value_counts().to_dict())
            pr_ctks.update(sub["ctk"].unique())
            pr_ctk_year_pairs += len(sub)

        # check whether file is sorted by year (informs pass-2 strategy)
        cmin, cmax = int(yr.min()), int(yr.max())
        if prev_year_max_seen is not None and cmin < prev_year_max_seen:
            sorted_by_year = False
        prev_year_max_seen = max(prev_year_max_seen or cmin, cmax)

        el = time.time() - t0
        print(f"  {total_rows:,} rows scanned | PR rows so far {sum(pr_zip_rows.values()):,} | {el:,.0f}s", flush=True)

# ---- outputs ----
uni = pd.DataFrame(
    [(z, c, pr_zip_years[z][0], pr_zip_years[z][1]) for z, c in sorted(pr_zip_rows.items())],
    columns=["zip", "n_rows", "first_year", "last_year"],
)
uni.to_csv(os.path.join(OUT, "pr_zip_universe.csv"), index=False)

yy = pd.DataFrame(
    [(int(y), int(pr_year_rows.get(y, 0)), int(year_rows.get(y, 0))) for y in sorted(year_rows)],
    columns=["year", "pr_rows", "all_rows"],
)
yy.to_csv(os.path.join(OUT, "pr_zip_year_counts.csv"), index=False)

pd.Series(sorted(pr_ctks), name="ctk").to_csv(os.path.join(OUT, "pr_ctks.csv"), index=False)

summary = [
    f"Source: {SRC}",
    f"Total rows: {total_rows:,}",
    f"Rows with non-numeric/short zip: {bad_zip_rows:,}",
    f"Zip length distribution: {dict(sorted(zip_len_counts.items()))}",
    f"File appears sorted by year: {sorted_by_year}",
    "",
    f"DISTINCT PR ZIPCODES (006/007/009): {len(pr_zip_rows):,}",
    f"PR person-year rows: {sum(pr_zip_rows.values()):,}",
    f"Distinct consumers ever in a PR zip: {len(pr_ctks):,}",
    "",
    "PR rows by year:",
    yy.to_string(index=False),
    "",
    "Top 15 PR zips by rows:",
    uni.sort_values("n_rows", ascending=False).head(15).to_string(index=False),
]
with open(os.path.join(OUT, "scan_summary.txt"), "w") as f:
    f.write("\n".join(summary))
print("\n".join(summary))
