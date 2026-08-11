"""
One LaTeX table per figure: pooled Pre, pooled Post, Post-Pre, R2/pseudo-R2,
observations, and Y/N fixed-effects rows per specification.

Conventions
-----------
* Post-Pre standard errors assume independence between the two pooled
  regressions (they are estimated separately by lpdid) -- an approximation,
  flagged in each table note.
* lpdid has no single-regression R2 (each horizon/pool is its own long-
  difference regression); those cells show "--". Sale-level OLS and Poisson
  tables parse N / (pseudo-)R2 from the estimation logs.
* Observations = the pooled-post regression's N where the estimator provides
  it (lpdid obs column; log-parsed otherwise).
* Stars: * p<0.10, ** p<0.05, *** p<0.01 (normal approx from b/se).

Outputs: output/tables/tab_<figure>.tex + tables_preview.tex (compilable).
"""

import csv, math, os, re
from collections import defaultdict

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
O1 = os.path.join(REPO, "output", "design1")
O2 = os.path.join(REPO, "output", "design2")
D2 = os.path.join(REPO, "data", "design2")
OUT = os.path.join(REPO, "output", "tables")
os.makedirs(OUT, exist_ok=True)


# ---------- helpers ----------
def stars(b, se):
    if se in (None, 0) or (isinstance(se, float) and (math.isnan(se) or se == 0)):
        return ""
    z = abs(b / se)
    return "***" if z > 2.576 else "**" if z > 1.960 else "*" if z > 1.645 else ""


def cell(b, se, scale=1.0):
    if b is None:
        return ("--", "")
    b2, se2 = b * scale, (se * scale if se is not None else None)
    top = f"{b2:+.2f}{stars(b2, se2)}"
    bot = f"({se2:.2f})" if se2 is not None else ""
    return (top, bot)


def load_csv(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def f(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


class Spec:
    """One table column."""
    def __init__(self, label, pre=None, pre_se=None, post=None, post_se=None,
                 r2="--", nobs="--", fe=None, extra=None):
        self.label = label
        self.pre, self.pre_se = pre, pre_se
        self.post, self.post_se = post, post_se
        self.r2, self.nobs = r2, nobs
        self.fe = fe or {}
        self.extra = extra or {}   # ordered dict of extra stat rows
        self.pmd = None            # (b, se) from the pre-mean-differenced regression

    def postpre(self):
        # prefer the single-regression PMD estimate; fall back to the
        # arithmetic difference with an independence-approximation SE
        if self.pmd is not None:
            return self.pmd
        if self.post is None or self.pre is None:
            return (None, None)
        se = None
        if self.post_se is not None and self.pre_se is not None:
            se = math.sqrt(self.post_se**2 + self.pre_se**2)
        return (self.post - self.pre, se)


def emit_table(fname, title, specs, fe_rows, note, scale=1.0, extra_rows=()):
    ncol = len(specs)
    lines = []
    lines.append("\\begin{table}[htbp]\\centering")
    lines.append(f"\\caption{{{title}}}")
    lines.append("\\begin{tabular}{l" + "c"*ncol + "}")
    lines.append("\\toprule")
    lines.append(" & " + " & ".join(f"({i+1})" for i in range(ncol)) + " \\\\")
    lines.append(" & " + " & ".join(s.label for s in specs) + " \\\\")
    lines.append("\\midrule")

    def statrows(name, vals):
        tops, bots = [], []
        for b, se in vals:
            t, bo = cell(b, se, scale)
            tops.append(t); bots.append(bo)
        lines.append(name + " & " + " & ".join(tops) + " \\\\")
        if any(bots):
            lines.append(" & " + " & ".join(bots) + " \\\\")

    statrows("Pooled pre", [(s.pre, s.pre_se) for s in specs])
    statrows("Pooled post", [(s.post, s.post_se) for s in specs])
    statrows("Post $-$ pre", [s.postpre() for s in specs])
    for label in extra_rows:
        statrows(label, [s.extra.get(label, (None, None)) for s in specs])
    lines.append("\\midrule")
    for fe in fe_rows:
        lines.append(fe + " & " + " & ".join(s.fe.get(fe, "--") for s in specs) + " \\\\")
    lines.append("R$^2$ & " + " & ".join(str(s.r2) for s in specs) + " \\\\")
    lines.append("Observations & " + " & ".join(str(s.nobs) for s in specs) + " \\\\")
    lines.append("\\bottomrule")
    lines.append("\\end{tabular}")
    lines.append(f"\\begin{{minipage}}{{0.95\\textwidth}}\\vspace{{2pt}}\\scriptsize {note}\\end{{minipage}}")
    lines.append("\\end{table}")
    with open(os.path.join(OUT, fname), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("wrote", fname)


NOTE_LPDID = ("LP-DiD pooled estimates; pre and post pooled coefficients are relative to the $t{-}1$ base. "
              "Post$-$pre is estimated in a single LP-DiD regression via pre-mean differencing "
              "(Dube, Girardi, Jord\\`a and Taylor 2023): dependent variable "
              "$\\frac{1}{4}\\sum_{h=0}^{3} y_{t+h} - \\frac{1}{4}\\sum_{\\tau=t-4}^{t-1} y_{\\tau}$ "
              "on treatment entry with calendar-time effects, clean-control sample; its SE, $R^2$ and "
              "Observations come from that regression. Coefficients are 100$\\times$log points "
              "(shares in pp). SEs clustered by unit (cell/tract).")

R2MAP = {}
for _r2file in ("pmd_stats.csv", "pmd_stats_withinevent.csv"):
    _r2path = os.path.join(OUT, _r2file)
    if os.path.exists(_r2path):
        for _r in load_csv(_r2path):
            R2MAP[_r["test"]] = (f(_r["b"]), f(_r["se"]), f(_r["r2"]),
                                 int(f(_r["nobs"])) if f(_r["nobs"]) else None)

def apply_r2(sp, key):
    if sp is None or key not in R2MAP:
        return sp
    b, se, r2, n = R2MAP[key]
    sp.pmd = (b, se)
    sp.r2 = f"{r2:.3f}" if r2 is not None else "--"
    if n:
        sp.nobs = f"{n:,}"
    return sp


def lp_pooled(rows, test):
    pre = next((r for r in rows if r["test"] == test and r.get("matrix_type") == "pooled"
                and r["rowname"].lower() == "pre"), None)
    post = next((r for r in rows if r["test"] == test and r.get("matrix_type") == "pooled"
                 and r["rowname"].lower() == "post"), None)
    if not pre or not post:
        return None
    return dict(pre=f(pre["c1"]), pre_se=f(pre["c2"]),
                post=f(post["c1"]), post_se=f(post["c2"]),
                nobs=int(f(post["c7"])) if f(post["c7"]) else "--")


def parse_log_stats(path, marker_re, n_re, r2_re):
    """Return list of (N, R2) in order of marker occurrences."""
    out = []
    cur = None
    for line in open(path, encoding="utf-8", errors="replace"):
        # skip the command-echo line (". di ...") -- only count the printed banner
        if re.search(marker_re, line) and not line.lstrip().startswith(". di"):
            cur = [None, None]
            out.append(cur)
        if cur is not None:
            m = re.search(n_re, line)
            if m and cur[0] is None:
                cur[0] = int(m.group(1).replace(",", ""))
            m = re.search(r2_re, line)
            if m and cur[1] is None:
                cur[1] = float(m.group(1))
    return out


FE_D1 = ["Calendar-year effects", "Event$\\times$ring cell differencing",
         "Hedonic controls"]
def d1fe(hed="N"):
    return {"Calendar-year effects": "Y",
            "Event$\\times$ring cell differencing": "Y",
            "Hedonic controls": hed}


def main():
    # ================= Design 1 robustness figures =================
    rob = load_csv(os.path.join(O1, "robustness_coefs.csv"))
    have_mt = "matrix_type" in rob[0]
    if not have_mt:
        print("WARNING: robustness_coefs.csv lacks pooled rows; D1 tables skipped")
    def spec_from(test, label):
        p = lp_pooled(rob, test)
        if p is None:
            return None
        return apply_r2(Spec(label, pre=p["pre"], pre_se=p["pre_se"], post=p["post"],
                    post_se=p["post_se"], nobs=p["nobs"], fe=d1fe()), test)

    figs = [
        ("tab_fig1_baseline.tex", "Baseline ring event study (fig.\\ 1)",
         [("T1_baseline", "Near 0--250m")]),
        ("tab_fig2_placebo.tex", "Investor vs placebo purchases (fig.\\ 2)",
         [("T6_real_far750", "Investor events"), ("T6_placebo", "Placebo events")]),
        ("tab_fig3_gradient.tex", "Spatial gradient (fig.\\ 3)",
         [("T1_baseline", "Near 0--250m"), ("T3_gradient_gap", "Gap 250--400m")]),
        ("tab_fig4_dose.tex", "By local event density (fig.\\ 4)",
         [("T4_dose_low", "0--2 events"), ("T4_dose_mid", "3--25"), ("T4_dose_high", "$>$25")]),
        ("tab_fig5_late.tex", "Censoring robustness (fig.\\ 5)",
         [("T1_baseline", "All events"), ("T5_late", "Events 2018+")]),
        ("tab_fig6_composition.tex", "Composition outcomes (fig.\\ 6)",
         [("T2_comp_lnstru", "ln structure"), ("T2_comp_lncab", "ln lot size"),
          ("T2_comp_subu", "Sub-unit share"), ("T2_comp_vac", "Vacant share")]),
        ("tab_fig7_parties.tex", "Non-Hispanic-named party shares (fig.\\ 7)",
         [("T7_buy_nh", "Buyers"), ("T7_sell_nh", "Sellers")]),
        ("tab_fig8_transitions.tex", "Transaction transitions (fig.\\ 8)",
         [("T7_isl2main", "Hisp.$\\to$non-Hisp."), ("T7_main2main", "non-H.$\\to$non-H.")]),
        ("tab_fig9_inclinvestors.tex", "Buyer-margin decomposition (fig.\\ 9)",
         [("T1_baseline", "Non-investor sales"), ("T8_incl_investors", "All sales")]),
        ("tab_fig10_hispbuyers.tex", "Locals-only prices (fig.\\ 10)",
         [("T1_baseline", "All market sales"), ("T8_hisp_buyers", "Hispanic-named buyers")]),
    ]
    if have_mt:
        for fname, title, series in figs:
            specs = [s for t, lab in series if (s := spec_from(t, lab))]
            if specs:
                emit_table(fname, title, specs, FE_D1, NOTE_LPDID, scale=100)

    # ================= Decay / ladder =================
    dec = load_csv(os.path.join(O1, "decay_coefs.csv"))
    order = [("D_0_250", "0--250m"), ("D_250_500", "250--500m"),
             ("D_500_1000", "500--1000m"), ("D_1000_1500", "1000--1500m")]
    specs = []
    for t, lab in order:
        p = lp_pooled(dec, t)
        if p:
            specs.append(apply_r2(Spec(lab, pre=p["pre"], pre_se=p["pre_se"], post=p["post"],
                              post_se=p["post_se"], nobs=p["nobs"], fe=d1fe()), t))
    emit_table("tab_figD1to3_decay.tex",
               "Spatial decay, 1.5--2km control band (figs.\\ D1--D3)",
               specs, FE_D1, NOTE_LPDID + " Control band 1{,}500--2{,}000m.", scale=100)

    lad = load_csv(os.path.join(O1, "ladder_coefs.csv"))
    lorder = [("C_400_1000", "400--1000m"), ("C_1000_1500", "1000--1500m"),
              ("C_1500_2000", "1500--2000m"), ("C_2000_2500", "2000--2500m"),
              ("C_2500_3500", "2500--3500m")]
    specs = []
    for t, lab in lorder:
        p = lp_pooled(lad, t)
        if p:
            specs.append(apply_r2(Spec(lab, pre=p["pre"], pre_se=p["pre_se"], post=p["post"],
                              post_se=p["post_se"], nobs=p["nobs"], fe=d1fe()), t))
    emit_table("tab_figD4_ladder.tex",
               "Control-band ladder, treated ring 0--250m (fig.\\ D4)",
               specs, FE_D1, NOTE_LPDID + " Columns are alternative control bands.", scale=100)

    # ============ Detrended wide-band tables (3.5km, 5km) ============
    def detrended_table(csvname, fname, title, order, prefix=""):
        rows = load_csv(os.path.join(O1, csvname))
        specs = []
        for t, lab in order:
            ev = [r for r in rows if r["test"] == t and r["matrix_type"] == "event"]
            num = den = 0.0
            for r in ev:
                rn = r["rowname"]
                h = -int(rn[3:]) if rn.startswith("pre") else int(rn[3:])
                if h < 0:
                    num += (f(r["c1"]) or 0) * (h + 1)
                    den += (h + 1) ** 2
            s = num / den if den else 0.0
            p = lp_pooled(rows, t)
            if not p:
                continue
            sp = Spec(lab, pre=p["pre"], pre_se=p["pre_se"], post=p["post"],
                      post_se=p["post_se"], nobs=p["nobs"], fe=d1fe())
            sp.extra["Pre-drift (per yr)"] = (s, None)
            sp.extra["Detrended post"] = (p["post"] - 2.5 * s, p["post_se"])
            r2key = t.replace("D_", prefix + "_", 1) if prefix else t
            specs.append(apply_r2(sp, r2key))
        emit_table(fname, title, specs, FE_D1,
                   NOTE_LPDID + " Detrended post subtracts the per-bin linear pre-drift "
                   "(fit through the base period) times the mean post horizon (2.5); "
                   "its SE is the unadjusted pooled-post SE (trend treated as known).",
                   scale=100, extra_rows=("Pre-drift (per yr)", "Detrended post"))

    detrended_table("decay_coefs_3p5km.csv", "tab_figD5to7_detrended3p5.tex",
                    "Wide-band decay with linear detrending, 2.5--3.5km control (figs.\\ D5--D7)",
                    [("D_0_250", "0--250m"), ("D_250_500", "250--500m"),
                     ("D_500_1000", "500--1000m"), ("D_1000_1750", "1000--1750m"),
                     ("D_1750_2500", "1750--2500m")], prefix="D35")
    detrended_table("decay_coefs_5km.csv", "tab_figD8to11_detrended5km.tex",
                    "Decay to 4km with linear detrending, 4--5km control (figs.\\ D8--D11)",
                    [("D_0_250", "0--250m"), ("D_250_500", "250--500m"),
                     ("D_500_1000", "500--1000m"), ("D_1000_1750", "1000--1750m"),
                     ("D_1750_2500", "1750--2500m"), ("D_2500_3500", "2500--3500m"),
                     ("D_3500_4000", "3500--4000m")], prefix="D5K")

    # ================= figD12 sale-level =================
    sl = load_csv(os.path.join(O1, "salelevel_coefs.csv"))
    stats = parse_log_stats(os.path.join(O1, "salelevel_results.log"),
                            r"===== S[12]:", r"Number of obs\s*=\s*([\d,]+)",
                            r"R-squared\s*=\s*([0-9.]+)")
    FE_SL = ["Event$\\times$ring FE", "Event$\\times$year FE", "Hedonic controls"]
    specs = []
    p = lp_pooled(rob, "T1_baseline") if have_mt else None
    if p:
        sp = Spec("LP-DiD cells", pre=p["pre"], pre_se=p["pre_se"], post=p["post"],
                  post_se=p["post_se"], nobs=p["nobs"],
                  fe={"Event$\\times$ring FE": "(diff.)", "Event$\\times$year FE": "(diff.)",
                      "Hedonic controls": "N"})
        apply_r2(sp, "T1_baseline")
        specs.append(sp)
    # within-event LP-DiD column (absorb(event x year)), parsed from its log
    _wlog = os.path.join(O1, "withinevent_results.log")
    if os.path.exists(_wlog):
        seg = open(_wlog, encoding="utf-8", errors="replace").read()
        # "WITHIN-EVENT" appears twice (command echo + printed banner): take the
        # last segment, which follows the banner and contains the matrices
        if "WITHIN-EVENT" in seg and "e(pooled_results)[2,7]" in seg.split("WITHIN-EVENT")[-1]:
            seg = seg.split("WITHIN-EVENT")[-1].split("e(pooled_results)[2,7]")[1]
            def _nums(l):
                return [float(x) for x in re.findall(r"-?\d*\.\d+|-?\d+", l)]
            prl = [l for l in seg.splitlines() if re.match(r"\s*Pre\s", l)]
            pol = [l for l in seg.splitlines() if re.match(r"\s*Post\s", l)]
            if len(prl) >= 2 and len(pol) >= 2:
                pr1, po1, po2 = _nums(prl[0]), _nums(pol[0]), _nums(pol[1])
                sp = Spec("LP-DiD within-event",
                          pre=pr1[0], pre_se=pr1[1],
                          post=po1[0], post_se=po1[1],
                          nobs=f"{int(po2[-1]):,}",
                          fe={"Event$\\times$ring FE": "(diff.)",
                              "Event$\\times$year FE": "Y",
                              "Hedonic controls": "N"})
                # single-regression PMD post-pre with absorb(event x year)
                # (design1_withinevent_pmd.do) -> proper SE, R2, N
                apply_r2(sp, "T1_withinevent")
                specs.append(sp)
    for i, (spec_id, lab, hed) in enumerate([("S1_pooled", "Sale-level OLS", "N"),
                                             ("S2_hedonic", "Sale-level OLS", "Y")]):
        r = next(x for x in sl if x["spec"] == spec_id and f(x["h"]) == 99)
        n, r2 = (stats[i] if i < len(stats) else (None, None))
        sp = Spec(lab, pre=None, pre_se=None, post=None, post_se=None,
                  r2=f"{r2:.3f}" if r2 else "--",
                  nobs=f"{n:,}" if n else "--",
                  fe={"Event$\\times$ring FE": "Y", "Event$\\times$year FE": "Y",
                      "Hedonic controls": hed})
        # near x post is itself the post-pre differential: report it in the
        # same row as the LP-DiD post-pre estimates
        sp.pmd = (f(r["b"]) * 100, f(r["se"]) * 100)
        specs.append(sp)
    # scale: lpdid columns are in natural-log units -> x100 for display
    # (including the PMD post-pre tuple where present)
    for sp in specs:
        if not sp.label.startswith("LP-DiD"):
            continue
        for a in ("pre", "post"):
            v = getattr(sp, a)
            if v is not None:
                setattr(sp, a, v * 100)
                setattr(sp, a + "_se", getattr(sp, a + "_se") * 100)
        if sp.pmd is not None:
            sp.pmd = (sp.pmd[0] * 100, sp.pmd[1] * 100 if sp.pmd[1] else None)
    emit_table("tab_figD12_salelevel.tex",
               "Estimation-approach robustness (fig.\\ D12)", specs, FE_SL,
               "The Post$-$pre row is the comparable differential across estimators. "
               "Column (1): cell-level LP-DiD, pooled never-treated controls; post$-$pre, R$^2$ and N "
               "from the single pre-mean-differenced regression (Dube et al.\\ 2023). Column (2): the same "
               "PMD regression with event$\\times$calendar-year effects absorbed (within-event "
               "identification: each near ring vs its own event's far ring); pooled pre/post are the "
               "corresponding lpdid coefficients. Columns (3)-(4): stacked sale-level OLS; the "
               "near$\\times$post coefficient is itself the differential, SEs clustered by event. "
               "Long-differencing subsumes event$\\times$ring FE in the LP-DiD columns. "
               "100$\\times$log points.")

    # ================= Design 2 tract tables =================
    d2 = load_csv(os.path.join(O2, "design2_coefs.csv"))
    FE_D2 = ["Tract differencing (LP-DiD)", "Calendar-year effects", "County FE"]
    def d2spec(test, label, county="N"):
        p = lp_pooled(d2, test)
        if p is None:
            return None
        return apply_r2(Spec(label, pre=p["pre"], pre_se=p["pre_se"], post=p["post"],
                    post_se=p["post_se"], nobs=p["nobs"],
                    fe={"Tract differencing (LP-DiD)": "Y", "Calendar-year effects": "Y",
                        "County FE": county}), test)
    emit_table("tab_figT1_tractprice.tex", "Tract-level price event study (fig.\\ T1)",
               [d2spec("T_lnhp_base", "Weighted price"),
                d2spec("T_lnhp_fips", "Weighted price", "Y"),
                d2spec("T_lnhpsimple_base", "Simple mean")],
               FE_D2, NOTE_LPDID, scale=1)
    emit_table("tab_figT2_dose.tex", "Tract price effects by concentration (fig.\\ T2)",
               [d2spec("T_lnhp_dose5", "5+ purchases"),
                d2spec("T_lnhp_dose14", "1--4 purchases")],
               FE_D2, NOTE_LPDID, scale=1)
    emit_table("tab_figT3_volume.tex", "Tract transaction volume (fig.\\ T3)",
               [d2spec("T_lnsales_base", "ln sales")],
               FE_D2, NOTE_LPDID + " Pre-trends fail for this outcome; descriptive only.", scale=1)

    # figT4 reconciliation table
    trt = {r["tract_geoid"]: int(r["n_events"]) for r in load_csv(os.path.join(D2, "design2_tract_treatment.csv"))}
    pred = load_csv(os.path.join(D2, "design2_ring_prediction.csv"))
    groups = {"All treated": lambda n: True, "1--4 purchases": lambda n: 1 <= n <= 4,
              "5+ purchases": lambda n: n >= 5}
    obs = {"All treated": lp_pooled(d2, "T_lnhp_base"),
           "1--4 purchases": lp_pooled(d2, "T_lnhp_dose14"),
           "5+ purchases": lp_pooled(d2, "T_lnhp_dose5")}
    lines = ["\\begin{table}[htbp]\\centering",
             "\\caption{Observed tract effects vs ring-implied predictions (fig.\\ T4)}",
             "\\begin{tabular}{lcccc}", "\\toprule",
             "Group & Observed & Pred.\\ (central) & Pred.\\ (conserv.) & Gap \\\\", "\\midrule"]
    for g, sel in groups.items():
        pc = [f(r["pred_central_vw"]) for r in pred if r["tract_geoid"] in trt
              and sel(trt[r["tract_geoid"]]) and r["pred_central_vw"]]
        pk = [f(r["pred_conserv_vw"]) for r in pred if r["tract_geoid"] in trt
              and sel(trt[r["tract_geoid"]]) and r["pred_conserv_vw"]]
        o = obs[g]
        mc, mk = 100 * sum(pc) / len(pc), 100 * sum(pk) / len(pk)
        top, bot = cell(o["post"], o["post_se"])   # design2 lnhp already 100x
        lines.append(f"{g} & {top} & {mc:+.2f} & {mk:+.2f} & {o['post']-mc:+.2f} \\\\")
        lines.append(f" & {bot} & & & \\\\")
    lines += ["\\bottomrule", "\\end{tabular}",
              "\\begin{minipage}{0.95\\textwidth}\\vspace{2pt}\\scriptsize Observed: LP-DiD pooled post "
              "(group vs never-treated tracts), SEs clustered by tract. Predictions: stock-value-weighted "
              "distance-gradient effects over each treated tract's parcels, averaged within group. "
              "Gap = observed minus central prediction. 100$\\times$log points.\\end{minipage}",
              "\\end{table}"]
    with open(os.path.join(OUT, "tab_figT4_reconciliation.tex"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("wrote tab_figT4_reconciliation.tex")

    # ================= HMDA tables =================
    def hmda_tables(coefs_csv, log_name, suffix, cfe):
        hm = load_csv(os.path.join(O2, coefs_csv))
        stats = parse_log_stats(os.path.join(O2, log_name),
                                r"===== POISSON pooled post|===== POISSON county x year FE",
                                r"(?:Number of obs|No\. of obs)\s*=\s*([\d,]+)", r"Pseudo R2\s*=\s*([0-9.]+)")
        # base log: markers alternate ES/pooled per outcome for the base file;
        # cfe log: one marker per outcome (ES), pooled unmarked -> fall back to obs from ES.
        FE_H = ["Tract FE", "Year FE", "County$\\times$Year FE"]
        fe = {"Tract FE": "Y", "Year FE": "--" if cfe else "Y",
              "County$\\times$Year FE": "Y" if cfe else "N"}
        outs = {"purch_oo_n": "Owner-occ.\\ purch.", "purch_nonoo_n": "Non-owner purch.",
                "refi_n": "Rate/term refi", "cashout_n": "Cash-out refi", "total_n": "Total"}
        def hspec(o, lab, idx):
            po = next((x for x in hm if x["outcome"] == o and f(x["h"]) == 99), None)
            pre_vals = [(f(x["b"]), f(x["se"])) for x in hm
                        if x["outcome"] == o and f(x["h"]) in (-3, -2)]
            pre = sum(v[0] for v in pre_vals) / len(pre_vals) if pre_vals else None
            pre_se = (math.sqrt(sum(v[1] ** 2 for v in pre_vals)) / len(pre_vals)
                      if pre_vals and all(v[1] for v in pre_vals) else None)
            n, r2 = (stats[idx] if idx < len(stats) else (None, None))
            return Spec(lab, pre=pre * 100 if pre is not None else None,
                        pre_se=pre_se * 100 if pre_se else None,
                        post=f(po["b"]) * 100 if po else None,
                        post_se=f(po["se"]) * 100 if po else None,
                        r2=f"{r2:.3f}" if r2 else "--", nobs=f"{n:,}" if n else "--",
                        fe=dict(fe))
        note = ("Poisson (PPML) origination counts; pooled post is the single treat coefficient; "
                "pooled pre is the average of the $h=-3,-2$ event-study leads (independence-approx.\\ SE). "
                "100$\\times$coefficient $\\approx$ percent. SEs clustered by tract. Pseudo-$R^2$ reported.")
        idxs = {"purch_oo_n": 0, "purch_nonoo_n": 1, "refi_n": 2, "cashout_n": 3, "total_n": 4}
        emit_table(f"tab_figH1{suffix}_purchases.tex",
                   f"HMDA purchase originations{' (county-adjusted)' if cfe else ''} (fig.\\ H1{suffix})",
                   [hspec("purch_oo_n", outs["purch_oo_n"], idxs["purch_oo_n"]),
                    hspec("purch_nonoo_n", outs["purch_nonoo_n"], idxs["purch_nonoo_n"])],
                   FE_H, note)
        emit_table(f"tab_figH2{suffix}_refis.tex",
                   f"HMDA refinancing originations{' (county-adjusted)' if cfe else ''} (fig.\\ H2{suffix})",
                   [hspec("refi_n", outs["refi_n"], idxs["refi_n"]),
                    hspec("cashout_n", outs["cashout_n"], idxs["cashout_n"])],
                   FE_H, note)
        emit_table(f"tab_figH3{suffix}_total.tex",
                   f"HMDA total originations{' (county-adjusted)' if cfe else ''} (fig.\\ H3{suffix})",
                   [hspec("total_n", outs["total_n"], idxs["total_n"])],
                   FE_H, note)

    hmda_tables("hmda_pois_coefs.csv", "hmda_poisson.log", "", False)
    hmda_tables("hmda_pois_cfe_coefs.csv", "hmda_poisson_cfe.log", "cfe", True)

    # ================= preview wrapper =================
    tabs = sorted(x for x in os.listdir(OUT) if x.startswith("tab_") and x.endswith(".tex"))
    with open(os.path.join(OUT, "tables_preview.tex"), "w", encoding="utf-8") as fh:
        fh.write("\\documentclass[10pt]{article}\n\\usepackage[margin=0.8in]{geometry}\n"
                 "\\usepackage{booktabs}\n\\begin{document}\n"
                 "\\section*{Tables: one per figure}\n")
        for t in tabs:
            fh.write(f"\\input{{{t}}}\n\\clearpage\n")
        fh.write("\\end{document}\n")
    print(f"wrote tables_preview.tex ({len(tabs)} tables)")


if __name__ == "__main__":
    main()
