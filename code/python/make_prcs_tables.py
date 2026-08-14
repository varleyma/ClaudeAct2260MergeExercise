"""
Two Design-2 tables from the 2010 PRCS baseline covariates:

1. tab_balance_prcs2010.tex -- balance of 2010 (pre-Act 22) tract
   characteristics across never-treated / 1-4-purchase / 5+-purchase tracts,
   with normalized differences (Imbens-Rubin) vs the never-treated pool.

2. tab_controls_robustness.tex -- spec ladder from
   output/design2/controls_robustness.csv: for each outcome
   (1) base TWFE, (2) + county-year FE, (3) + county-year FE and
   2010 controls x Post. Two six-column panels.

Both in the house table style ([H], bold-caption paragraph, scalebox,
onehalfspacing, toprule/midrule skeleton, Yes/No FE rows).
"""

import csv, math, os, statistics

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
D2 = os.path.join(REPO, "data", "design2")
O2 = os.path.join(REPO, "output", "design2")
OUT = os.path.join(REPO, "output", "tables")

SIGNOTE = ("Statistical significance levels are indicated as follows: "
           "*** $p < 0.01$, ** $p < 0.05$, * $p < 0.10$.")


def load_csv(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def f(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def stars(b, se):
    if not se:
        return ""
    z = abs(b / se)
    return "***" if z > 2.576 else "**" if z > 1.960 else "*" if z > 1.645 else ""


# ---------------------------------------------------------------- balance ---
CTRL_LABELS = [
    ("med_hh_inc", "Median household income (\\$)", "{:,.0f}"),
    ("med_value", "Median home value (\\$)", "{:,.0f}"),
    ("med_rent", "Median gross rent (\\$)", "{:,.0f}"),
    ("poverty", "Poverty rate", "{:.3f}"),
    ("ba_share", "BA+ share (25+)", "{:.3f}"),
    ("renter_share", "Renter share", "{:.3f}"),
    ("vacancy", "Vacancy rate", "{:.3f}"),
    ("seasonal_share", "Seasonal-home share", "{:.3f}"),
    ("mainland_share", "Born-in-mainland share", "{:.3f}"),
    ("pop", "Population", "{:,.0f}"),
]


def _diff_reg(y, t, county, within_county):
    """OLS of y on treated dummy (optionally demeaned within county).
    Returns (b, p) with HC1 robust SEs."""
    n = len(y)
    if within_county:
        from collections import defaultdict as dd
        gy, gt, gn = dd(float), dd(float), dd(int)
        for yi, ti, ci in zip(y, t, county):
            gy[ci] += yi; gt[ci] += ti; gn[ci] += 1
        yt = [yi - gy[ci] / gn[ci] for yi, ci in zip(y, county)]
        tt = [ti - gt[ci] / gn[ci] for ti, ci in zip(t, county)]
        k = len(gn) + 1
    else:
        my, mt = sum(y) / n, sum(t) / n
        yt = [yi - my for yi in y]
        tt = [ti - mt for ti in t]
        k = 2
    stt = sum(v * v for v in tt)
    if stt == 0 or n <= k:
        return None, None
    b = sum(a * v for a, v in zip(yt, tt)) / stt
    e = [a - b * v for a, v in zip(yt, tt)]
    meat = sum(v * v * ei * ei for v, ei in zip(tt, e))
    var = meat / (stt ** 2) * n / (n - k)
    se = math.sqrt(var)
    z = abs(b / se) if se > 0 else 0.0
    p = 2 * (1 - 0.5 * (1 + math.erf(z / math.sqrt(2))))
    return b, p


def balance_table():
    trt = {}
    for r in load_csv(os.path.join(D2, "design2_tract_treatment.csv")):
        try:
            trt[r["tract_geoid"]] = int(r["n_events"])
        except (ValueError, KeyError):
            pass
    rows = load_csv(os.path.join(D2, "prcs2010_tract_controls.csv"))

    def pstars(p):
        return "***" if p < 0.01 else "**" if p < 0.05 else "*" if p < 0.10 else ""

    def mstats(sel, c):
        v = [f(r[c]) for r in rows if sel(trt.get(r["tract_geoid"], 0))
             and f(r[c]) is not None]
        if len(v) < 2:
            return None, None, 0
        return statistics.mean(v), statistics.stdev(v), len(v)

    lines = ["\\begin{table}[H]", "\\centering"]
    note = ("This table presents summary statistics for 2010 PRCS (ACS "
            "2006--2010 5-year) tract characteristics --- all pre-determined "
            "relative to Act 22 (January 2012) --- separated by tracts that "
            "ever receive an identified decree-era investor purchase (treated) "
            "and tracts that never do. Column (7) reports the raw mean "
            "difference between treated and never-treated tracts and column "
            "(8) the difference after residualizing out municipio (county) "
            "fixed effects, with heteroskedasticity-robust $p$-values in "
            "parentheses. Dollar variables in 2010 dollars; shares in [0,1]. "
            "2010 tracts are mapped to 2020 boundaries by largest land "
            "overlap, population-weighted. " + SIGNOTE)
    lines.append(f"\\caption{{\\textbf{{2010 Characteristics by Tract Treatment Status}} {note}}}")
    lines += ["\\scalebox{0.75}{", "\\onehalfspacing",
              "\\begin{tabular}{lccccccccccc}",
              "\\toprule\\midrule",
              " & \\multicolumn{3}{c}{Treated Tracts} & & \\multicolumn{3}{c}{Never-Treated Tracts} & "
              "& Mean Diff. & & Adj. Mean Diff. \\\\",
              "\\cmidrule{2-4}\\cmidrule{6-8}\\cmidrule{10-10}\\cmidrule{12-12}"
              " & & & & & & & & & [(1) -- (4)] & & [(1) -- (4)] \\\\",
              " & Mean & Std. Dev. & Observations & & Mean & Std. Dev. & Observations & & $p$-value & & $p$-value \\\\",
              "\\cmidrule{2-4}\\cmidrule{6-8}\\cmidrule{10-10}\\cmidrule{12-12}"
              " & (1) & (2) & (3) & & (4) & (5) & (6) & & (7) & & (8) \\\\",
              "\\midrule"]
    for c, lab, fmt in CTRL_LABELS:
        m1, s1, n1 = mstats(lambda n: n >= 1, c)
        m0, s0, n0 = mstats(lambda n: n == 0, c)
        yy, tt, cc = [], [], []
        for r in rows:
            v = f(r[c])
            if v is None:
                continue
            yy.append(v)
            tt.append(1.0 if trt.get(r["tract_geoid"], 0) >= 1 else 0.0)
            cc.append(r["tract_geoid"][:5])
        braw, praw = _diff_reg(yy, tt, cc, False)
        badj, padj = _diff_reg(yy, tt, cc, True)
        dfmt = "{:,.0f}" if fmt.endswith("0f}") else "{:.3f}"
        cells = [fmt.format(m1), fmt.format(s1), f"{n1:,}", "",
                 fmt.format(m0), fmt.format(s0), f"{n0:,}", "",
                 dfmt.format(braw) + pstars(praw), "",
                 dfmt.format(badj) + pstars(padj)]
        lines.append(f"    \\multicolumn{{1}}{{l}}{{{lab}}} & " + " & ".join(cells) + " \\\\")
        lines.append(" & & & & & & & & & " + f"({praw:.3f})" + " & & " + f"({padj:.3f})" + " \\\\")
    lines += ["\\midrule\\bottomrule", "\\end{tabular}", "}",
              "\\label{tab:balance_prcs2010}", "\\end{table}"]
    with open(os.path.join(OUT, "tab_balance_prcs2010.tex"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("wrote tab_balance_prcs2010.tex")


# ----------------------------------------------------------- spec ladder ---
def ladder_table():
    cr = {(r["outcome"], int(f(r["spec"]))): r
          for r in load_csv(os.path.join(O2, "controls_robustness.csv"))}
    _ring = os.path.join(REPO, "output", "design1", "controls_robustness_ring.csv")
    if os.path.exists(_ring):
        for r in load_csv(_ring):
            cr[(r["outcome"], int(f(r["spec"])))] = r

    def bse(o, s, scale=1.0):
        r = cr[(o, s)]
        b, se = f(r["b"]) * scale, f(r["se"]) * scale
        return f"{b:.2f}{stars(b, se)}", f"({se:.2f})"

    def stat(o, s, key, fmt):
        return fmt.format(f(cr[(o, s)][key]))

    note = ("This table reports Treated coefficients from the paper's "
            "baseline estimator --- the pre-mean-differenced LP-DiD (Dube et "
            "al.\\ 2023; $H{=}3$, $k{=}4$, clean-control sample: newly "
            "treated tracts at onset plus never-treated tracts) --- under "
            "three specifications per outcome: (1) calendar-year effects; "
            "(2) county$\\times$year effects; (3) adds ten standardized 2010 "
            "PRCS baseline characteristics (median household income, home "
            "value, and gross rent; poverty, BA+, renter, vacancy, "
            "seasonal-home, and mainland-born shares; log population) "
            "interacted with the unit's post-treatment indicator (which "
            "turns on at the tract's first identified purchase; in the "
            "differenced clean sample this is $X \\times$ treatment entry), "
            "so the column (3) Treated coefficient is the effect at "
            "sample-mean 2010 characteristics. Tract fixed effects are "
            "subsumed by the long-differencing. "
            "Panel A: tract log price (Red Atlas, count-weighted annual "
            "mean) and log mean purchase-borrower income (HMDA, 2012--2024), "
            "both scaled by 100. Panel B: purchase origination counts by "
            "borrower ethnicity as $100 \\times \\text{asinh}$ (Poisson does "
            "not compose with pre-mean differencing; the Poisson event "
            "studies appear in the figures). Robust standard errors are "
            "clustered at the tract level and reported in parentheses. "
            + SIGNOTE)

    lines = ["\\begin{table}[H]", "\\centering",
             f"\\caption{{\\textbf{{Tract-level treatment effects are robust to county-year shocks and baseline-trend controls}} {note}}}",
             "\\scalebox{1.0}{", "\\onehalfspacing", "\\begin{tabular}{lcccccc}",
             "\\toprule\\midrule"]

    def panel(title, o1, o1lab, o2, o2lab, coef_lab, scale1, scale2, r2lab,
              felabel="Tract FE"):
        out = [f" & \\multicolumn{{3}}{{c}}{{\\textit{{{o1lab}}}}} & \\multicolumn{{3}}{{c}}{{\\textit{{{o2lab}}}}} \\\\",
               "\\cmidrule(lr){2-4} \\cmidrule(lr){5-7}",
               " & (1) & (2) & (3) & (1) & (2) & (3) \\\\", "\\midrule"]
        tops, bots = [], []
        for o, sc in ((o1, scale1), (o2, scale2)):
            for s in (1, 2, 3):
                t, b = bse(o, s, sc)
                tops.append(t); bots.append(b)
        out.append(f"    {coef_lab} & " + " & ".join(tops) + " \\\\")
        out.append(" & " + " & ".join(bots) + " \\\\")
        out.append(" & & & & & & \\\\")
        obs = [stat(o, s, "nobs", "{:,.0f}") for o in (o1, o2) for s in (1, 2, 3)]
        r2 = [stat(o, s, "r2", "{:.3f}") for o in (o1, o2) for s in (1, 2, 3)]
        out.append("    Observations & " + " & ".join(obs) + " \\\\")
        out.append(f"    {r2lab} & " + " & ".join(r2) + " \\\\")
        out.append(f"    {felabel} & Yes & Yes & Yes & Yes & Yes & Yes \\\\")
        out.append("    Calendar-year effects & Yes & No & No & Yes & No & No \\\\")
        out.append("    County-year effects & No & Yes & Yes & No & Yes & Yes \\\\")
        out.append("    2010 Controls $\\times$ Post-Treat. & No & No & Yes & No & No & Yes \\\\")
        return out

    lines += ["\\multicolumn{7}{l}{\\textbf{Panel A: prices and borrower income}} \\\\"]
    lines += panel("A", "lnhp", "100 $\\times$ Log(Price)", "lninc_all",
                   "100 $\\times$ Log(Borrower Income)", "Treated", 1, 1, "R-squared",
                   felabel="Tract differencing (LP-DiD)")
    lines += ["\\midrule",
              "\\multicolumn{7}{l}{\\textbf{Panel B: purchase originations by borrower ethnicity ($100\\times$asinh)}} \\\\"]
    lines += panel("B", "purch_hisp_n", "Hispanic Purchases", "purch_nonhisp_n",
                   "Non-Hispanic Purchases", "Treated", 1, 1, "R-squared",
                   felabel="Tract differencing (LP-DiD)")
    lines += ["\\midrule\\bottomrule", "\\end{tabular}", "}",
              "\\label{tab:controls_robustness}", "\\end{table}"]
    with open(os.path.join(OUT, "tab_controls_robustness.tex"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("wrote tab_controls_robustness.tex")

    # ---- ring design ladder, own table -------------------------------------
    if ("ring_lnp", 1) not in cr:
        return
    rnote = ("This table subjects the ring design's estimates to the same "
             "specification ladder as the tract-level outcomes, using the "
             "paper's baseline estimator throughout: the pre-mean-differenced "
             "LP-DiD on the event$\\times$ring cell panel ($H{=}3$, $k{=}4$; "
             "clean-control sample: newly treated near cells at onset plus "
             "never-treated cells; specification (1) reproduces the baseline "
             "table exactly). Specifications: (1) calendar-year effects; (2) "
             "county$\\times$year effects (the county is the event's "
             "municipio); (3) adds ten standardized 2010 PRCS characteristics "
             "of the event's tract interacted with the cell's post-treatment "
             "indicator ($X \\times$ treatment entry in the differenced clean "
             "sample), so the column (3) Treated coefficient is the effect "
             "at sample-mean 2010 characteristics. Cell fixed effects are "
             "subsumed by the long-differencing. Outcomes: cell mean log sale price "
             "($\\times$100) and the net Hispanic-to-non-Hispanic ownership "
             "conversion rate per classified sale (percentage points). "
             "Robust standard errors are clustered at the cell level and "
             "reported in parentheses. " + SIGNOTE)
    lines = ["\\begin{table}[H]", "\\centering",
             f"\\caption{{\\textbf{{Ring-design treatment effects are robust to county-year shocks and baseline-trend controls}} {rnote}}}",
             "\\scalebox{1.0}{", "\\onehalfspacing", "\\begin{tabular}{lcccccc}",
             "\\toprule\\midrule"]
    lines += panel("A", "ring_lnp", "100 $\\times$ Log(Price)", "ring_netin",
                   "Net H$\\to$NH Conversion (pp)", "Treated", 100, 100,
                   "R-squared", felabel="Cell differencing (LP-DiD)")
    lines += ["\\midrule\\bottomrule", "\\end{tabular}", "}",
              "\\label{tab:ring_controls_robustness}", "\\end{table}"]
    with open(os.path.join(OUT, "tab_ring_controls_robustness.tex"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("wrote tab_ring_controls_robustness.tex")


if __name__ == "__main__":
    balance_table()
    ladder_table()


def copy_main():
    import shutil
    main = os.path.join(OUT, "main")
    os.makedirs(main, exist_ok=True)
    for t in ("tab_controls_robustness.tex", "tab_ring_controls_robustness.tex"):
        p = os.path.join(OUT, t)
        if os.path.exists(p):
            shutil.copy(p, main)
    print("copied ladders to output/tables/main/")


copy_main()
