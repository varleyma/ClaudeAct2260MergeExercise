"""Pass 2: build PR zip-level outmigration from the Experian header panel.

Reads (READ-ONLY) the 2GB Dropbox .dta in chunks, keeps all rows for consumers
ever observed in a PR zip (from pass-1 pr_ctks.csv), then computes year-over-year
transitions out of PR zipcodes under two definitions:
  - move_any      : next-year zip differs from current zip (incl. within-PR moves)
  - move_off_pr   : next-year zip is outside PR (mainland/other territory)
  - move_within_pr: different zip but still PR (= move_any - move_off_pr)

Primary risk set = consumers observed in a PR zip in year t AND observed in t+1
(consecutive years). Consumers not seen in t+1 are counted as attrition, not moves.

Outputs (GitHub repo only):
  data/experian/pr_consumer_histories.csv    - full panel rows for PR-ever ctks
  data/experian/pr_outmigration_zip_year.csv - origin zip x year counts + rates
  data/experian/pr_outmigration_island_year.csv - island totals by year
  data/experian/migration_summary.txt
"""
import os
import time
import pandas as pd

SRC = r"C:\Users\mva284\Dropbox\ClaudeAct2260MergeExercise\data\raw\header2005_2023_ctk.dta"
OUT = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise\data\experian"
CHUNK = 2_000_000

pr_ctks = set(pd.read_csv(os.path.join(OUT, "pr_ctks.csv"))["ctk"])
print(f"PR-ever consumers: {len(pr_ctks):,}")

# ---- pass 2 extraction ----
parts = []
t0 = time.time()
with pd.read_stata(SRC, iterator=True) as rdr:
    total = 0
    while True:
        try:
            df = rdr.read(CHUNK)
        except StopIteration:
            break
        if df is None or len(df) == 0:
            break
        total += len(df)
        sub = df[df["ctk"].isin(pr_ctks)].copy()
        if len(sub):
            parts.append(sub)
        print(f"  {total:,} rows | kept {sum(len(p) for p in parts):,} | {time.time()-t0:,.0f}s", flush=True)

hist = pd.concat(parts, ignore_index=True)
del parts
hist["year"] = hist["year"].astype("int32")
hist["zip_cd"] = hist["zip_cd"].str.strip().str.zfill(5)
hist["is_pr"] = hist["zip_cd"].str.startswith(("006", "007", "009"))

# duplicate ctk-year check (keep first, report)
n_dup = int(hist.duplicated(["ctk", "year"]).sum())
if n_dup:
    hist = hist.sort_values(["ctk", "year"]).drop_duplicates(["ctk", "year"], keep="first")

hist = hist.sort_values(["ctk", "year"]).reset_index(drop=True)
hist.to_csv(os.path.join(OUT, "pr_consumer_histories.csv"), index=False)
print(f"Histories: {len(hist):,} rows, {hist['ctk'].nunique():,} consumers, dup ctk-year dropped: {n_dup:,}")

# ---- transitions ----
hist["next_year"] = hist.groupby("ctk")["year"].shift(-1)
hist["next_zip"] = hist.groupby("ctk")["zip_cd"].shift(-1)
hist["next_is_pr"] = hist.groupby("ctk")["is_pr"].shift(-1)

# risk set: in PR at t, observed at t+1 (consecutive)
base = hist[hist["is_pr"]].copy()
base["observed_next"] = base["next_year"] == base["year"] + 1
rs = base[base["observed_next"]].copy()
rs["move_any"] = rs["next_zip"] != rs["zip_cd"]
rs["move_off_pr"] = ~rs["next_is_pr"].astype(bool)
rs["move_within_pr"] = rs["move_any"] & rs["next_is_pr"].astype(bool)

def agg(g):
    return pd.Series({
        "n_at_risk": len(g),
        "n_stay": int((~g["move_any"]).sum()),
        "n_move_any": int(g["move_any"].sum()),
        "n_move_within_pr": int(g["move_within_pr"].sum()),
        "n_move_off_pr": int(g["move_off_pr"].sum()),
    })

zy = rs.groupby(["zip_cd", "year"]).apply(agg, include_groups=False).reset_index()
# attrition: in PR at t, not observed at t+1 (last panel year 2023 excluded)
att = (base[(~base["observed_next"]) & (base["year"] < 2023)]
       .groupby(["zip_cd", "year"]).size().rename("n_attrit").reset_index())
zy = zy.merge(att, on=["zip_cd", "year"], how="left").fillna({"n_attrit": 0})
zy["n_attrit"] = zy["n_attrit"].astype(int)
for c in ["move_any", "move_within_pr", "move_off_pr"]:
    zy[f"rate_{c}"] = zy[f"n_{c}"] / zy["n_at_risk"]
zy = zy.rename(columns={"zip_cd": "zip"})
zy.to_csv(os.path.join(OUT, "pr_outmigration_zip_year.csv"), index=False)

isl = zy.groupby("year")[["n_at_risk", "n_stay", "n_move_any",
                          "n_move_within_pr", "n_move_off_pr", "n_attrit"]].sum().reset_index()
for c in ["move_any", "move_within_pr", "move_off_pr"]:
    isl[f"rate_{c}"] = isl[f"n_{c}"] / isl["n_at_risk"]
isl.to_csv(os.path.join(OUT, "pr_outmigration_island_year.csv"), index=False)

lines = [
    f"Histories: {len(hist):,} rows / {hist['ctk'].nunique():,} consumers (dup ctk-year dropped: {n_dup:,})",
    f"PR person-years at risk (obs t & t+1): {int(zy['n_at_risk'].sum()):,}",
    f"Attrition person-years (in PR at t<2023, unobserved t+1): {int(zy['n_attrit'].sum()):,}",
    f"Zip-year cells: {len(zy):,} | zips: {zy['zip'].nunique()}",
    "",
    "Island-level annual rates:",
    isl.round(4).to_string(index=False),
]
with open(os.path.join(OUT, "migration_summary.txt"), "w") as f:
    f.write("\n".join(lines))
print("\n".join(lines))
