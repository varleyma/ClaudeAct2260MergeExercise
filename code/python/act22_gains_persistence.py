"""
act22_gains_persistence.py
==========================

Persistence of exempt capital-gains realization across years, using
the fuzzy-merge person panel (act22_panel_full.dta). Purpose: referee
rebuttal for "the exempt income could be returns on island
investments." Island exits (selling a PR business or property) are
LUMPY ONE-OFFS; liquid portfolio trading produces RECURRING annual
realizations. If exempt gains are reported by the same people year
after year, the trading interpretation wins.

DESIGN
  - Panel: panel_id x report_year (merge pipeline output; one row per
    person-year, source record identified by the per-vintage
    filename_* columns).
  - Income joined from the raw report CSVs by filename (first
    non-blank among filename, filename_2015_2018..filename_2023);
    cells > $1B nulled (4 parse errors, see
    act22_income_composition.py).
  - gains_t = 1{exempt capital gains > 0 in year t}.

STATISTICS
  1. Transition: P(gains_{t+1} > 0 | gains_t > 0) vs
     P(gains_{t+1} > 0 | gains_t = 0), over consecutive observed
     year pairs.
  2. Within-person recurrence: among persons observed >= 3 years with
     >= 1 gains year, the fraction of observed years with gains
     (distribution + share with gains in ALL observed years).
  3. Dollar persistence: share of total exempt-gains dollars accruing
     to persons with gains in 3+ (and 2+) distinct years.

OUTPUTS
  output/act22_income/act22_gains_persistence_hist.png
  output/act22_income/act22_gains_persistence_stats.csv
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

# income lookup by filename
fr = []
for f in FILES:
    d = pd.read_csv(RAW / f, low_memory=False)
    for c in ("income_capital_gains_exempt",):
        if c not in d.columns:
            d[c] = np.nan
    fr.append(d[["filename", "income_capital_gains_exempt"]])
inc = pd.concat(fr).drop_duplicates("filename")
inc["g"] = (pd.to_numeric(inc["income_capital_gains_exempt"],
                          errors="coerce").clip(lower=0))
inc.loc[inc["g"] > 1e9, "g"] = np.nan
g_map = inc.set_index("filename")["g"]

panel = pd.read_stata(REPO / "data" / "clean" / "act22_panel_full.dta")
fn_cols = ["filename", "filename_2015_2018", "filename_2019",
           "filename_2020", "filename_2021", "filename_2022",
           "filename_2023"]
fn = panel[fn_cols].replace("", np.nan).bfill(axis=1).iloc[:, 0]
panel["gains"] = fn.map(g_map)
matched = panel["gains"].notna().sum()
print(f"panel rows: {len(panel)}; income matched: {matched} "
      f"({matched/len(panel):.0%})")
panel["gains"] = panel["gains"].fillna(0.0)
panel["has_gains"] = panel["gains"] > 0
panel = panel.dropna(subset=["report_year"])
panel["report_year"] = panel["report_year"].astype(int)
panel = (panel.sort_values(["panel_id", "report_year"])
         .drop_duplicates(["panel_id", "report_year"]))

# ---------------------------------------------------------------------------
# 1. Transition probabilities over consecutive observed year pairs
# ---------------------------------------------------------------------------
panel["next_year"] = panel.groupby("panel_id")["report_year"].shift(-1)
panel["next_gains"] = panel.groupby("panel_id")["has_gains"].shift(-1)
pairs = panel[panel["next_year"] == panel["report_year"] + 1]
p_stay = pairs.loc[pairs["has_gains"], "next_gains"].mean()
p_entry = pairs.loc[~pairs["has_gains"], "next_gains"].mean()
base = panel["has_gains"].mean()
print(f"\nConsecutive-year pairs: {len(pairs)}")
print(f"P(gains t+1 | gains t)    = {p_stay:.1%} "
      f"(n={int(pairs['has_gains'].sum())})")
print(f"P(gains t+1 | no gains t) = {p_entry:.1%}")
print(f"Unconditional P(gains)    = {base:.1%}  -> persistence ratio "
      f"{p_stay/p_entry:.1f}x")

# ---------------------------------------------------------------------------
# 2. Within-person recurrence (persons observed >= 3 years, ever gains)
# ---------------------------------------------------------------------------
per = (panel.groupby("panel_id")
       .agg(n_years=("report_year", "nunique"),
            n_gain_years=("has_gains", "sum"),
            tot_gains=("gains", "sum")))
multi = per[(per["n_years"] >= 3) & (per["n_gain_years"] >= 1)].copy()
multi["frac"] = multi["n_gain_years"] / multi["n_years"]
print(f"\nPersons observed >=3 years with >=1 gains year: {len(multi)}")
print(f"median fraction of observed years with gains: "
      f"{multi['frac'].median():.2f}")
print(f"gains in ALL observed years: {(multi['frac'] >= 0.999).mean():.1%}")
print(f"gains in majority of observed years: "
      f"{(multi['frac'] > 0.5).mean():.1%}")

# ---------------------------------------------------------------------------
# 3. Dollar persistence
# ---------------------------------------------------------------------------
tot = per["tot_gains"].sum()
for k in (2, 3):
    sh = per.loc[per["n_gain_years"] >= k, "tot_gains"].sum() / tot
    print(f"share of exempt-gains dollars from persons with gains in "
          f">={k} distinct years: {sh:.1%}")
# one-off comparison
one_off = per.loc[per["n_gain_years"] == 1, "tot_gains"].sum() / tot
print(f"share from single-gains-year persons (the 'lumpy exit' "
      f"signature, incl. persons observed once): {one_off:.1%}")

stats = pd.DataFrame([
    ("pairs_n", len(pairs)), ("p_stay", p_stay), ("p_entry", p_entry),
    ("base_rate", base), ("persistence_ratio", p_stay / p_entry),
    ("n_multi_persons", len(multi)),
    ("median_frac_gain_years", multi["frac"].median()),
    ("share_all_years", (multi["frac"] >= 0.999).mean()),
    ("share_majority_years", (multi["frac"] > 0.5).mean()),
    ("dollar_share_2plus_years",
     per.loc[per["n_gain_years"] >= 2, "tot_gains"].sum() / tot),
    ("dollar_share_3plus_years",
     per.loc[per["n_gain_years"] >= 3, "tot_gains"].sum() / tot),
    ("dollar_share_single_year", one_off),
], columns=["stat", "value"])
stats.to_csv(OUT / "act22_gains_persistence_stats.csv", index=False)

# ---------------------------------------------------------------------------
# Figure: distribution of within-person gains recurrence
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# 4. Horizon profile: beta_H from the LPM  1{gains_{t+H}} = a + b 1{gains_t}
#    (slope = P(gains t+H | gains t) - P(gains t+H | no gains t)),
#    analytic CR1 SEs clustered by person
# ---------------------------------------------------------------------------
HMAX = 5
key = panel.set_index(["panel_id", "report_year"])["has_gains"]
pid_codes = panel["panel_id"].astype("category")
prof_rows = []
for H in range(1, HMAX + 1):
    tgt = pd.MultiIndex.from_arrays(
        [panel["panel_id"], panel["report_year"] + H])
    nxt = key.reindex(tgt).to_numpy()
    ok = ~pd.isna(nxt)
    pid = pid_codes.cat.codes.to_numpy()[ok]
    g0 = panel["has_gains"].to_numpy()[ok].astype(float)
    gH = nxt[ok].astype(float)
    X = np.column_stack([np.ones_like(g0), g0])
    XtX_inv = np.linalg.inv(X.T @ X)
    beta = XtX_inv @ (X.T @ gH)
    u = gH - X @ beta
    clusters = np.unique(pid)
    meat = np.zeros((2, 2))
    for g in clusters:
        m = pid == g
        s = X[m].T @ u[m]
        meat += np.outer(s, s)
    Gc, n, k = len(clusters), len(gH), 2
    V = (Gc / (Gc - 1)) * ((n - 1) / (n - k)) * XtX_inv @ meat @ XtX_inv
    se = np.sqrt(V[1, 1])
    prof_rows.append({"H": H, "beta": beta[1], "se": se,
                      "lo": beta[1] - 1.96 * se,
                      "hi": beta[1] + 1.96 * se,
                      "t": beta[1] / se, "n_pairs": n,
                      "n_clusters": Gc,
                      "p_cond": gH[g0 == 1].mean(),
                      "p_uncond": gH[g0 == 0].mean()})
prof = pd.DataFrame(prof_rows)
print("\nHorizon profile beta_H (LPM, SEs clustered by person):")
print(prof.round(3).to_string(index=False))
prof.to_csv(OUT / "act22_gains_persistence_horizon.csv", index=False)

import matplotlib  # noqa: E402
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

GRAY = "#999999"
fig, ax = plt.subplots(figsize=(8, 5))
bins = np.linspace(0, 1, 11)
ax.hist(multi["frac"], bins=bins, color="#1f77b4", edgecolor="white",
        weights=np.full(len(multi), 100.0 / len(multi)))
ax.set_title("Recurrence of exempt capital-gains realization\n"
             "within Act 22 filers (matched report panel)",
             fontsize=12, fontweight="bold")
ax.set_xlabel("Fraction of a filer's observed report years with "
              "positive exempt gains")
ax.set_ylabel("% of filers")
ax.spines[["top", "right"]].set_visible(False)
fig.text(0.01, 0.01,
         "Filers observed in >=3 reporting years with >=1 gains year "
         f"(n={len(multi)}), fuzzy-merge panel. Lumpy island exits "
         "predict mass at the left; recurring portfolio trading "
         "predicts mass at the right.", fontsize=7, color=GRAY)
fig.tight_layout(rect=(0, 0.04, 1, 1))
fig.savefig(OUT / "act22_gains_persistence_hist.png", dpi=200)
plt.close(fig)

fig, ax = plt.subplots(figsize=(8, 5))
ax.errorbar(prof["H"], prof["beta"],
            yerr=[prof["beta"] - prof["lo"], prof["hi"] - prof["beta"]],
            color="#1f77b4", marker="o", linestyle="none", capsize=3,
            elinewidth=1.2, markersize=5,
            label=r"$\beta_H$: effect of gains in $t$ on P(gains in $t+H$)")
ax.axhline(0, color=GRAY, lw=1, ls="--")
ax.set_xticks(prof["H"])
ax.set_ylim(bottom=min(0, prof["lo"].min() - 0.02))
ax.set_title("Persistence of exempt capital-gains realization:\n"
             "horizon profile within Act 22 filers",
             fontsize=12, fontweight="bold")
ax.set_xlabel("Horizon H (years ahead)")
ax.set_ylabel("Change in probability of exempt gains at t+H")
ax.spines[["top", "right"]].set_visible(False)
ax.legend(frameon=False)
fig.text(0.01, 0.01,
         "LPM slope of 1{gains t+H} on 1{gains t} over all person-year "
         "pairs with both years observed (fuzzy-merge panel); 95% CI, "
         "SEs clustered by person. Lumpy one-off exits predict ~0 at "
         "every horizon.", fontsize=7, color=GRAY)
fig.tight_layout(rect=(0, 0.04, 1, 1))
fig.savefig(OUT / "act22_gains_persistence_horizon.png", dpi=200)
plt.close(fig)
print("\nWrote figures + stats to " + str(OUT))
