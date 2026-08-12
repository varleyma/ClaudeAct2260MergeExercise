"""In-migration into PR zips from the Experian header histories.

Uses data/experian/pr_consumer_histories.csv (full panel rows for every
consumer ever observed in a PR zip — so every arrival into a PR zip has its
origin row available, including mainland origins).

For each consumer-year in a PR zip (arrival year t), with the previous
observation at t-1 (consecutive):
  in_any         - previous zip differs (any origin)
  in_within_pr   - previous zip is a different PR zip
  in_off_island  - previous zip is outside PR (mainland/territories)
Separately: new_entry = first-ever panel observation is this PR zip-year
(new credit file, NOT a move; reported but kept out of migration rates).

Rate denominator = stock: consumers observed in the zip that year.

Outputs:
  data/experian/pr_inmigration_zip_year.csv        - zip x year counts + rates
  data/experian/pr_inmigration_island_year.csv     - island totals
  data/experian/pr_inmigration_zip_year_treated.csv- merged w/ zip treatment
  data/experian/inmigration_summary.txt
"""
import os
import pandas as pd

OUT = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise\data\experian"

h = pd.read_csv(os.path.join(OUT, "pr_consumer_histories.csv"),
                dtype={"zip_cd": str})
h = h.sort_values(["ctk", "year"]).reset_index(drop=True)
h["is_pr"] = h["zip_cd"].str.startswith(("006", "007", "009"))

h["prev_year"] = h.groupby("ctk")["year"].shift(1)
h["prev_zip"] = h.groupby("ctk")["zip_cd"].shift(1)
h["prev_is_pr"] = h.groupby("ctk")["is_pr"].shift(1)
h["first_obs"] = h["prev_year"].isna()

pr = h[h["is_pr"]].copy()
pr["consec"] = pr["prev_year"] == pr["year"] - 1
pr["in_any"] = pr["consec"] & (pr["prev_zip"] != pr["zip_cd"])
pr["in_within_pr"] = pr["in_any"] & pr["prev_is_pr"].astype("boolean").fillna(False).astype(bool)
pr["in_off_island"] = pr["in_any"] & ~pr["prev_is_pr"].astype("boolean").fillna(True).astype(bool)
pr["new_entry"] = pr["first_obs"]
pr["gap_return"] = (~pr["consec"]) & (~pr["first_obs"])  # reappeared after gap

zy = (pr.groupby(["zip_cd", "year"])
      .agg(n_stock=("ctk", "size"),
           n_in_any=("in_any", "sum"),
           n_in_within_pr=("in_within_pr", "sum"),
           n_in_off_island=("in_off_island", "sum"),
           n_new_entry=("new_entry", "sum"),
           n_gap_return=("gap_return", "sum"))
      .reset_index().rename(columns={"zip_cd": "zip"}))
for c in ["in_any", "in_within_pr", "in_off_island"]:
    zy[f"rate_{c}"] = zy[f"n_{c}"] / zy["n_stock"]
zy.to_csv(os.path.join(OUT, "pr_inmigration_zip_year.csv"), index=False)

isl = zy.groupby("year")[[c for c in zy.columns if c.startswith("n_")]].sum().reset_index()
for c in ["in_any", "in_within_pr", "in_off_island"]:
    isl[f"rate_{c}"] = isl[f"n_{c}"] / isl["n_stock"]
isl.to_csv(os.path.join(OUT, "pr_inmigration_island_year.csv"), index=False)

trt = pd.read_csv(os.path.join(OUT, "zip_treatment.csv"), dtype={"zcta": str})
m = zy.merge(trt.rename(columns={"zcta": "zip"}), on="zip", how="left")
m.to_csv(os.path.join(OUT, "pr_inmigration_zip_year_treated.csv"), index=False)

lines = [
    f"PR person-years (stock): {int(zy['n_stock'].sum()):,} across {zy['zip'].nunique()} zips",
    f"Arrivals (consecutive-year moves into a PR zip): {int(zy['n_in_any'].sum()):,}"
    f" (within-PR {int(zy['n_in_within_pr'].sum()):,},"
    f" off-island {int(zy['n_in_off_island'].sum()):,})",
    f"New credit-file entries in PR zips: {int(zy['n_new_entry'].sum()):,} (excluded from rates)",
    f"Gap reappearances: {int(zy['n_gap_return'].sum()):,} (excluded from rates)",
    "",
    "Island-level annual in-migration (note 2005 = no prior year observable):",
    isl[isl.year > 2005][["year", "n_stock", "n_in_any", "n_in_within_pr", "n_in_off_island",
         "rate_in_any", "rate_in_within_pr", "rate_in_off_island"]].round(4).to_string(index=False),
]
with open(os.path.join(OUT, "inmigration_summary.txt"), "w") as f:
    f.write("\n".join(lines))
print("\n".join(lines))
