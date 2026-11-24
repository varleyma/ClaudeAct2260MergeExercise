"""
cbp_jobs_bound.py
=================

Cost-per-job FLOOR from the employment null (pitch section: canonical
object). Municipio-level CBP employment dose-DiD on investor-purchase
exposure; the 95% upper bound on jobs created divides into forgone
revenue to give a lower bound on cost per job, directly comparable to
the place-based literature's cost-per-job estimates.

DATA
  - CBP county-level (PR municipio = county, state FIPS 72) total
    employment (NAICS all-sector total '------'), 2012-2023, from the
    Census bulk files cbpYYpr_ia_co.zip (the API now requires a key;
    the bulk files do not); zips cached in data/third_party/cbp_muni/
    (delete to re-download).
  - Treatment: design-1 investor-purchase events (>=2012), municipio
    from tract_geoid[2:5]. High-exposure = municipios with >= 20
    events; cohort year = municipio's first event year.

SPEC
  log EMP_mt = alpha_m + lambda_t + effect, imputation estimator
  (FE fit on pre-cohort cells, effects = post residual means),
  post-pre difference with analytic CR1 SEs clustered by municipio
  via the equivalent two-way-within LPM-style regression on the
  post indicator (semi-dynamic, pre = reference).

JOBS BOUND
  jobs_upper = (exp(delta_hi) - 1) x pre-period employment base of
  high-exposure municipios. Cost floor = forgone revenue / jobs_upper
  under two cost conventions (single-year $1B; cumulative $3B).

OUTPUTS
  output/act22_income/cbp_jobs_eventstudy.png
  output/act22_income/cbp_jobs_bound.csv
"""

from __future__ import annotations

import json
import time
import urllib.request
from pathlib import Path

import numpy as np
import pandas as pd

REPO = Path(r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise")
CBP_DIR = REPO / "data" / "third_party" / "cbp_muni"
OUT = REPO / "output" / "act22_income"
CBP_DIR.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)

YEARS = list(range(2008, 2024))   # pre-period back to 2008 so the
                                  # 2012-cohort municipios have pre cells
HIGH_DOSE = 20          # events; high-exposure municipio threshold
COST_SINGLE_YEAR = 1e9  # draft convention: > $1B forgone in 2021 alone
COST_CUMULATIVE = 3e9   # conservative cumulative (21B exempt x ~15%)

# ---------------------------------------------------------------------------
# 1. CBP municipio x year employment (bulk PR/IA county files, cached)
# ---------------------------------------------------------------------------
frames = []
for y in YEARS:
    yy = f"{y % 100:02d}"
    cache = CBP_DIR / f"cbp{yy}pr_ia_co.zip"
    if not cache.exists():
        url = (f"https://www2.census.gov/programs-surveys/cbp/"
               f"datasets/{y}/cbp{yy}pr_ia_co.zip")
        req = urllib.request.Request(
            url, headers={"User-Agent": "research-data-pull"})
        with urllib.request.urlopen(req, timeout=120) as r:
            cache.write_bytes(r.read())
        time.sleep(1)
    d = pd.read_csv(cache, dtype=str)
    d.columns = [c.lower().strip() for c in d.columns]
    naics_col = "naics" if "naics" in d.columns else "naics2017"
    tot = d[(d["fipstate"] == "72")
            & (d[naics_col].str.strip() == "------")].copy()
    tot["emp"] = pd.to_numeric(tot["emp"], errors="coerce")
    # suppressed cells carry an empflag and emp=0 -> treat as missing
    if "empflag" in tot.columns:
        flagged = tot["empflag"].fillna("").str.strip() != ""
        tot.loc[flagged, "emp"] = np.nan
    tot.loc[tot["emp"] <= 0, "emp"] = np.nan
    frames.append(pd.DataFrame({
        "year": y, "county": tot["fipscty"].str.zfill(3),
        "emp": tot["emp"]}))
cbp = pd.concat(frames, ignore_index=True)
print(f"CBP: {cbp['county'].nunique()} municipios x "
      f"{cbp['year'].nunique()} years; "
      f"missing/suppressed EMP cells: {cbp['emp'].isna().sum()}")

# balanced sample: municipios with EMP observed in every year
ok = cbp.groupby("county")["emp"].transform(lambda s: s.notna().all())
cbp = cbp[ok]
print(f"balanced municipios: {cbp['county'].nunique()}")

# ---------------------------------------------------------------------------
# 2. Treatment from design-1 events
# ---------------------------------------------------------------------------
ev = pd.read_csv(REPO / "data" / "design1" / "design1_events.csv",
                 dtype={"tract_geoid": str})
ev["year"] = pd.to_datetime(ev["event_date"]).dt.year
ev = ev[ev["year"] >= 2012]
ev["county"] = ev["tract_geoid"].str[2:5]
dose = ev.groupby("county").agg(n_events=("event_id", "count"),
                                first_year=("year", "min"))
print(f"\nevents >=2012: {len(ev)}; municipios with events: {len(dose)}")
print("dose distribution (events per municipio):")
print(dose["n_events"].describe()[["min", "25%", "50%", "75%", "max"]]
      .round(0).to_string())
hi = dose[dose["n_events"] >= HIGH_DOSE]
print(f"high-exposure (>= {HIGH_DOSE} events): {len(hi)} municipios, "
      f"{hi['n_events'].sum()} events "
      f"({hi['n_events'].sum()/len(ev):.0%} of all)")

cbp = cbp.merge(dose, left_on="county", right_index=True, how="left")
cbp["n_events"] = cbp["n_events"].fillna(0)
cbp["treated"] = cbp["n_events"] >= HIGH_DOSE
cbp["e"] = np.where(cbp["treated"], cbp["first_year"], np.nan)
cbp["tau"] = cbp["year"] - cbp["e"]
cbp["lemp"] = np.log(cbp["emp"])

# ---------------------------------------------------------------------------
# 3. Imputation event study: FE on cells outside treated post-period
# ---------------------------------------------------------------------------
pre_mask = ~(cbp["treated"] & (cbp["tau"] >= 0))     # controls + treated pre
pid = cbp["county"].astype("category").cat.codes.to_numpy()
tid = (cbp["year"] - cbp["year"].min()).to_numpy()
n_m, n_t = pid.max() + 1, tid.max() + 1
y_ = cbp["lemp"].to_numpy()

alpha = np.zeros(n_m)
lam = np.zeros(n_t)
pm_, tm_, ym_ = pid[pre_mask], tid[pre_mask], y_[pre_mask]
cnt_p = np.bincount(pm_, minlength=n_m).astype(float)
cnt_t = np.bincount(tm_, minlength=n_t).astype(float)
for _ in range(100):
    alpha = np.bincount(pm_, ym_ - lam[tm_], minlength=n_m) / \
        np.maximum(cnt_p, 1)
    lam = np.bincount(tm_, ym_ - alpha[pm_], minlength=n_t) / \
        np.maximum(cnt_t, 1)
cbp["resid"] = y_ - alpha[pid] - lam[tid]
# a municipio with no pre/control cells has no fitted FE: drop it
no_fit = np.flatnonzero(cnt_p == 0)
if len(no_fit):
    bad = cbp["county"].astype("category").cat.categories[no_fit]
    print(f"WARNING: dropping munis with no pre/control cells: "
          f"{list(bad)}")
    cbp.loc[cbp["county"].isin(bad), "resid"] = np.nan

tr = cbp[cbp["treated"]]
es = (tr.groupby("tau")["resid"]
      .agg(["mean", "count"]).rename(columns={"mean": "effect"}))
# cluster (municipio) SE per tau
se_rows = []
for t_, g in tr.groupby("tau"):
    mu = g.groupby("county")["resid"].mean()
    se_rows.append({"tau": t_, "se": mu.std(ddof=1) / np.sqrt(len(mu)),
                    "n_munis": len(mu)})
es = es.merge(pd.DataFrame(se_rows).set_index("tau"), left_index=True,
              right_index=True)
es["lo"] = es["effect"] - 1.96 * es["se"]
es["hi"] = es["effect"] + 1.96 * es["se"]
print("\nEvent study, log employment, high-exposure municipios:")
print(es.round(3).to_string())

# post-pre scalar: mean post residual per treated muni, CR by muni
post = tr[tr["tau"] >= 0].groupby("county")["resid"].mean()
pre = tr[tr["tau"] < 0].groupby("county")["resid"].mean()
d_m = (post - pre).dropna()
delta = d_m.mean()
se_d = d_m.std(ddof=1) / np.sqrt(len(d_m))
hi95 = delta + 1.96 * se_d
print(f"\nPost-pre delta (log pts): {delta:.4f} (se {se_d:.4f}), "
      f"95% upper bound {hi95:.4f}, n_munis={len(d_m)}")

# ---------------------------------------------------------------------------
# 4. Jobs bound and cost-per-job floor
# ---------------------------------------------------------------------------
base_emp = tr[tr["tau"] < 0].groupby("county")["emp"].mean().sum()
jobs_point = (np.exp(delta) - 1) * base_emp
jobs_upper = (np.exp(hi95) - 1) * base_emp
print(f"\nhigh-exposure pre-period employment base: {base_emp:,.0f}")
print(f"jobs point estimate: {jobs_point:,.0f}; "
      f"95% upper bound: {jobs_upper:,.0f}")
for label, cost in (("single-year $1B", COST_SINGLE_YEAR),
                    ("cumulative $3B", COST_CUMULATIVE)):
    floor = cost / max(jobs_upper, 1)
    print(f"cost-per-job FLOOR ({label}): ${floor:,.0f}"
          + ("  [jobs bound <= 0: floor is infinite]"
             if jobs_upper <= 0 else ""))

pd.DataFrame({
    "stat": ["delta_logpts", "se", "upper95_logpts", "n_treated_munis",
             "base_emp", "jobs_point", "jobs_upper95",
             "floor_singleyear_1B", "floor_cumulative_3B"],
    "value": [delta, se_d, hi95, len(d_m), base_emp, jobs_point,
              jobs_upper,
              COST_SINGLE_YEAR / max(jobs_upper, 1),
              COST_CUMULATIVE / max(jobs_upper, 1)],
}).to_csv(OUT / "cbp_jobs_bound.csv", index=False)
es.reset_index().to_csv(OUT / "cbp_jobs_eventstudy.csv", index=False)

# ---------------------------------------------------------------------------
# Figure
# ---------------------------------------------------------------------------
import matplotlib  # noqa: E402
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

GRAY = "#999999"
w = es[(es.index >= -6) & (es.index <= 8)]
fig, ax = plt.subplots(figsize=(8, 5))
ax.errorbar(w.index, 100 * w["effect"],
            yerr=[100 * (w["effect"] - w["lo"]),
                  100 * (w["hi"] - w["effect"])],
            color="#1f77b4", marker="o", linestyle="none", capsize=3,
            elinewidth=1.2, markersize=5,
            label="High-exposure municipios (imputation, muni+year FE)")
ax.axvline(-0.5, color=GRAY, lw=1, ls="--")
ax.axhline(0, color=GRAY, lw=1, ls="--")
ax.set_title("Municipio employment around investor arrival:\n"
             "CBP total employment event study",
             fontsize=12, fontweight="bold")
ax.set_xlabel("Years since municipio's first investor-purchase event")
ax.set_ylabel("Log points x 100 vs municipio/year FE benchmark")
ax.spines[["top", "right"]].set_visible(False)
ax.legend(frameon=False, fontsize=9)
fig.text(0.01, 0.01,
         f"CBP county (=municipio) all-sector employment 2008-2023; "
         f"high-exposure = >= {HIGH_DOSE} design-1 events. FE fit on "
         "control and pre-event cells; 95% CI from municipio-level "
         "variation.", fontsize=7, color=GRAY)
fig.tight_layout(rect=(0, 0.04, 1, 1))
fig.savefig(OUT / "cbp_jobs_eventstudy.png", dpi=200)
plt.close(fig)
print("\nWrote figure + tables to " + str(OUT))
