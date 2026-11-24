"""
act22_income_composition.py
===========================

Composition of Act 22 beneficiaries' self-reported income across the
FULL report universe (all seven annual-report CSVs, 2015-2023
vintages), for the selection argument in the paper: the exempt income
is overwhelmingly CAPITAL GAINS rather than dividends or interest,
and a large majority of filers' exempt income is 100% capital gains
— the Form D movers are a closer look at the population, not a
strange subsample, and the population is short-horizon.

Descriptive only (reports exist only post-decree, so no pre-period).

INPUTS  (Dropbox, READ-ONLY)
  data/raw/Act22AnnualReports{2015-2018,2019,2020,2021,
           2022_format19,2022_format22,2023}.csv
  Income fields: income_{interest,dividends,capital_gains,wages,
  other_income}_{exempt,nonexempt} (the 2015-2018 vintage lacks the
  nonexempt interest/dividends and exempt wages/other columns).

RECORD HANDLING
  - One row per report PDF (filename). Duplicate filenames across
    source files are dropped keeping the first occurrence, in source
    order (same rule as the merge pipeline).
  - Year = current_reporting_year.
  - A record enters the exempt-composition sample if total exempt
    income > 0; the total-income sample if total reported income > 0.

OUTPUTS (repo)
  output/act22_income/act22_exempt_income_composition_by_year.png
  output/act22_income/act22_exempt_gains_share_filers.png
  output/act22_income/act22_income_composition_tables.csv
  console summary
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

DROPBOX = Path(r"C:\Users\mva284\Dropbox\ClaudeAct2260MergeExercise")
REPO = Path(r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise")
RAW = DROPBOX / "data" / "raw"
OUT = REPO / "output" / "act22_income"
OUT.mkdir(parents=True, exist_ok=True)

FILES = ["Act22AnnualReports2015-2018.csv", "Act22AnnualReports2019.csv",
         "Act22AnnualReports2020.csv", "Act22AnnualReports2021.csv",
         "Act22AnnualReports2022_format19.csv",
         "Act22AnnualReports2022_format22.csv",
         "Act22AnnualReports2023.csv"]
CATS = ["capital_gains", "dividends", "interest", "wages", "other_income"]
INC = [f"income_{c}_{s}" for c in CATS for s in ("exempt", "nonexempt")]

frames = []
for f in FILES:
    df = pd.read_csv(RAW / f, low_memory=False)
    keep = ["filename", "current_reporting_year"]
    for c in INC:
        if c not in df.columns:
            df[c] = np.nan
    frames.append(df[keep + INC].assign(source_file=f))
raw = pd.concat(frames, ignore_index=True)
n0 = len(raw)
raw = raw.drop_duplicates("filename", keep="first")
print(f"records: {n0} rows -> {len(raw)} after filename dedup")

raw["year"] = pd.to_numeric(raw["current_reporting_year"],
                            errors="coerce")
raw = raw[raw["year"].between(2012, 2023)]
# Parse-error scrub: a handful of cells are garbled by 4-6 orders of
# magnitude (e.g. a $59 TRILLION capital-gains cell; the next-largest
# value in any field is $580M). Null anything above $1B.
CAP = 1e9
n_bad = 0
for c in INC:
    raw[c] = pd.to_numeric(raw[c], errors="coerce").clip(lower=0)
    bad = raw[c] > CAP
    n_bad += int(bad.sum())
    raw.loc[bad, c] = np.nan
print(f"nulled {n_bad} income cells > $1B (parse errors)")

ex = {c: raw[f"income_{c}_exempt"].fillna(0.0) for c in CATS}
nx = {c: raw[f"income_{c}_nonexempt"].fillna(0.0) for c in CATS}
raw["exempt_total"] = sum(ex.values())
raw["total_income"] = raw["exempt_total"] + sum(nx.values())
raw["portfolio_income"] = sum((ex[c] + nx[c]) for c in
                              ("capital_gains", "dividends", "interest"))
raw["wages_all"] = ex["wages"] + nx["wages"]

# ---------------------------------------------------------------------------
# A. Aggregate composition of exempt income, by reporting year
# ---------------------------------------------------------------------------
agg = (raw.groupby("year")[[f"income_{c}_exempt" for c in CATS]]
       .sum())
agg.columns = CATS
agg_sh = agg.div(agg.sum(axis=1), axis=0)
n_by_year = raw.groupby("year")["filename"].count()
pos_ex = raw[raw["exempt_total"] > 0]
print("\nFilers per year / with positive exempt income:")
print(pd.DataFrame({"n": n_by_year,
                    "n_pos_exempt": pos_ex.groupby("year").size()})
      .fillna(0).astype(int).to_string())
print("\nAggregate exempt-income shares by year:")
print(agg_sh.round(3).to_string())
tot = agg.sum()
print("\nPooled 2012-2023 aggregate exempt income ($M and share):")
print(pd.DataFrame({"$M": (tot / 1e6).round(0),
                    "share": (tot / tot.sum()).round(3)}).to_string())

# ---------------------------------------------------------------------------
# B. Person-level: exempt income that is 100% (or >=90%) capital gains
# ---------------------------------------------------------------------------
pos = pos_ex.copy()
pos["gains_share_ex"] = (pos["income_capital_gains_exempt"].fillna(0)
                         / pos["exempt_total"])
pos["all_gains"] = pos["gains_share_ex"] >= 0.999
pos["mostly_gains"] = pos["gains_share_ex"] >= 0.90
by_year = pos.groupby("year").agg(
    n=("filename", "count"),
    share_all_gains=("all_gains", "mean"),
    share_90_gains=("mostly_gains", "mean"),
    median_gains_share=("gains_share_ex", "median"))
print("\nAmong filers with positive exempt income:")
print(by_year.round(3).to_string())
print(f"\nPOOLED: {pos['all_gains'].mean():.1%} of filer-years report "
      f"exempt income that is 100% capital gains "
      f"({pos['mostly_gains'].mean():.1%} at >=90%); "
      f"n={len(pos)} filer-years with positive exempt income.")

# ---------------------------------------------------------------------------
# B2. Horizon signal: among filers with ANY capital gains, share whose
#     gains are FULLY exempt (exempt = post-move appreciation only)
# ---------------------------------------------------------------------------
g_ex = raw["income_capital_gains_exempt"].fillna(0)
g_nx = raw["income_capital_gains_nonexempt"].fillna(0)
gains = raw[(g_ex + g_nx) > 0].copy()
gains["fully_exempt"] = (gains["income_capital_gains_nonexempt"]
                         .fillna(0) <= 0)
b2 = gains.groupby("year").agg(n=("filename", "count"),
                               share_fully_exempt=("fully_exempt",
                                                   "mean"))
print("\nAmong filers reporting ANY capital gains (horizon signal):")
print(b2.round(3).to_string())
print(f"POOLED: {gains['fully_exempt'].mean():.1%} of gains-reporting "
      f"filer-years have ALL gains fully exempt (n={len(gains)}).")

# ---------------------------------------------------------------------------
# C. Portfolio share of total reported income (the non-mechanical check)
# ---------------------------------------------------------------------------
ti = raw[raw["total_income"] > 0].copy()
ti["portfolio_share"] = ti["portfolio_income"] / ti["total_income"]
ti["no_wages"] = ti["wages_all"] <= 0
print(f"\nTotal-income sample (n={len(ti)} filer-years): "
      f"median portfolio share of total reported income = "
      f"{ti['portfolio_share'].median():.1%}; "
      f"{(ti['portfolio_share'] >= 0.999).mean():.1%} report ONLY "
      f"portfolio income; {ti['no_wages'].mean():.1%} report zero wages. "
      f"Aggregate portfolio share = "
      f"{ti['portfolio_income'].sum() / ti['total_income'].sum():.1%}.")

# tables out
rows_out = []
for y, r in agg_sh.iterrows():
    for c in CATS:
        rows_out.append({"panel": "A_aggregate_exempt_share", "year": int(y),
                         "measure": c, "value": r[c]})
for y, r in by_year.iterrows():
    for c in by_year.columns:
        rows_out.append({"panel": "B_filer_gains_share", "year": int(y),
                         "measure": c, "value": r[c]})
for y, r in b2.iterrows():
    for c in b2.columns:
        rows_out.append({"panel": "B2_gains_fully_exempt", "year": int(y),
                         "measure": c, "value": r[c]})
pd.DataFrame(rows_out).to_csv(
    OUT / "act22_income_composition_tables.csv", index=False)

# ---------------------------------------------------------------------------
# Figures (one graph per file)
# ---------------------------------------------------------------------------
import matplotlib  # noqa: E402
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

GRAY = "#999999"
COLORS = {"capital_gains": "#1f77b4", "dividends": "#ff7f0e",
          "interest": "#2ca02c", "wages": "#d62728",
          "other_income": "#9467bd"}
LAB = {"capital_gains": "Capital gains", "dividends": "Dividends",
       "interest": "Interest", "wages": "Wages (exempt)",
       "other_income": "Other"}

years = [int(y) for y in agg_sh.index if n_by_year.get(y, 0) >= 50]
plot_sh = agg_sh.loc[years]

fig, ax = plt.subplots(figsize=(8, 5))
bottom = np.zeros(len(years))
for c in CATS:
    vals = plot_sh[c].to_numpy()
    ax.bar(years, vals, bottom=bottom, color=COLORS[c], label=LAB[c],
           width=0.7)
    bottom += vals
ax.set_title("Composition of Act 22 beneficiaries' exempt income,\n"
             "by reporting year (all annual reports)",
             fontsize=12, fontweight="bold")
ax.set_xlabel("Reporting year")
ax.set_ylabel("Share of aggregate exempt income")
ax.set_ylim(0, 1)
ax.spines[["top", "right"]].set_visible(False)
ax.legend(frameon=False, ncol=5, loc="upper center",
          bbox_to_anchor=(0.5, -0.12), fontsize=8)
fig.text(0.01, 0.01, "Self-reported annual reports (DDEC FOIA); years "
         "with >=50 filings. Exempt categories per Act 22/60: interest, "
         "dividends, capital gains (wages/other exempt rare).",
         fontsize=7, color=GRAY)
fig.tight_layout(rect=(0, 0.04, 1, 1))
fig.savefig(OUT / "act22_exempt_income_composition_by_year.png", dpi=200)
plt.close(fig)

fig, ax = plt.subplots(figsize=(8, 5))
yrs2 = [int(y) for y in by_year.index if by_year.loc[y, "n"] >= 50]
b = by_year.loc[yrs2]
yrs3 = [int(y) for y in b2.index if b2.loc[y, "n"] >= 50]
ax.plot(yrs3, 100 * b2.loc[yrs3, "share_fully_exempt"], marker="o",
        color="#1f77b4",
        label="All capital gains fully exempt (among gains reporters)")
ax.plot(yrs2, 100 * b["share_90_gains"], marker="s", color="#ff7f0e",
        label="Capital gains \u2265 90% of exempt income")
ax.plot(yrs2, 100 * b["share_all_gains"], marker="^", color="#2ca02c",
        label="Exempt income is 100% capital gains")
ax.set_title("Horizon signals in Act 22 annual reports:\n"
             "capital-gains concentration of exempt income",
             fontsize=12, fontweight="bold")
ax.set_xlabel("Reporting year")
ax.set_ylabel("% of filers")
ax.set_ylim(0, 100)
ax.spines[["top", "right"]].set_visible(False)
ax.legend(frameon=False, loc="upper left", fontsize=9)
fig.text(0.01, 0.01, "Self-reported annual reports (DDEC FOIA); years "
         "with >=50 qualifying filers. Fully exempt gains = no "
         "non-exempt gains reported (exempt covers post-move "
         "appreciation only).", fontsize=7, color=GRAY)
fig.tight_layout(rect=(0, 0.04, 1, 1))
fig.savefig(OUT / "act22_exempt_gains_share_filers.png", dpi=200)
plt.close(fig)
print("\nWrote 2 figures + 1 table to " + str(OUT))
