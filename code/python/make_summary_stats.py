"""
Summary statistics table (tab_summary_stats.tex) covering the paper's main
samples, house style:

  Panel A  Ring design, market sales <=1km of an event (suite filters)
  Panel B  Tract-year price panel (Red Atlas, count-weighted annual means)
  Panel C  HMDA long panel, first-lien OO 1-4fam purchases, 2012-2024
  Panel D  2010 PRCS baseline tract characteristics

Columns: Mean, Std. Dev., P25, Median, P75, Observations.
"""

import csv, os, statistics

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
D1 = os.path.join(REPO, "data", "design1")
D2 = os.path.join(REPO, "data", "design2")
OUT = os.path.join(REPO, "output", "tables")
REDATLAS = r"C:\Users\mva284\Dropbox\Ley60PR\data\clean\monthly_data_red_atlas.csv"


def f(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def srow(label, vals, fmt):
    if not vals:
        return f"    \\multicolumn{{1}}{{l}}{{{label}}} & -- & -- & -- & -- & -- & 0 \\\\"
    vals = sorted(vals)
    n = len(vals)

    def q(p):
        i = p * (n - 1)
        lo = int(i)
        return vals[lo] + (i - lo) * (vals[min(lo + 1, n - 1)] - vals[lo])

    m = statistics.mean(vals)
    sd = statistics.stdev(vals) if n > 1 else 0.0
    cells = [fmt.format(v) for v in (m, sd, q(0.25), q(0.50), q(0.75))]
    return (f"    \\multicolumn{{1}}{{l}}{{{label}}} & " + " & ".join(cells)
            + f" & {n:,} \\\\")


def main():
    csv.field_size_limit(10_000_000)
    lines_a, lines_b, lines_c, lines_d = [], [], [], []

    # ---- Panel A: ring-design sale sample -----------------------------------
    price, lnp, nhbuy, i2m, m2i = [], [], [], [], []
    import math
    with open(os.path.join(D1, "design1_sale_event_pairs.csv"),
              newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if r["ring"] == "gap_250_400":
                continue
            if r["flag_junk_date"] == "True" or r["flag_nominal_price"] == "True":
                continue
            if r["sale_is_investor_parcel"] == "True":
                continue
            amt = f(r["SALESAMT"])
            etm = f(r["event_time_months"])
            if not amt or amt <= 0 or etm is None or not (-72 <= etm <= 60):
                continue
            try:
                if int(r["event_date"][:4]) < 2012:
                    continue
            except ValueError:
                continue
            price.append(amt)
            lnp.append(math.log(amt))
            b, s = r.get("buyer_nonhispanic", ""), r.get("seller_nonhispanic", "")
            if b in ("True", "False"):
                nhbuy.append(1.0 if b == "True" else 0.0)
                if s in ("True", "False"):
                    i2m.append(1.0 if (s == "False" and b == "True") else 0.0)
                    m2i.append(1.0 if (s == "True" and b == "False") else 0.0)
    lines_a.append(srow("Sale price (\\$000s)", [p / 1000 for p in price], "{:,.1f}"))
    lines_a.append(srow("Log sale price", lnp, "{:.2f}"))
    lines_a.append(srow("1\\{non-Hispanic-named buyer\\}", nhbuy, "{:.3f}"))
    lines_a.append(srow("1\\{Hisp.\\ seller $\\to$ non-Hisp.\\ buyer\\}", i2m, "{:.3f}"))
    lines_a.append(srow("1\\{non-Hisp.\\ seller $\\to$ Hisp.\\ buyer\\}", m2i, "{:.3f}"))

    # ---- Panel B: tract-year price panel ------------------------------------
    from collections import defaultdict
    pw, ns = defaultdict(float), defaultdict(float)
    with open(REDATLAS, newline="", encoding="utf-8") as fh:
        # Red Atlas headers are camelCase (geoTractId, NumberOfTransactions...)
        rdr = csv.reader(fh)
        hdr = [h.strip().lower() for h in next(rdr)]
        ix = {h: i for i, h in enumerate(hdr)}
        ip, in_, it, im = (ix["meantransactionpricepertract"],
                           ix["numberoftransactions"],
                           ix["geotractid"], ix["month"])
        for row in rdr:
            p, n = f(row[ip]), f(row[in_])
            if not p or not n or n <= 0:
                continue
            key = (row[it], row[im][:4])
            pw[key] += p * n
            ns[key] += n
    tprice = [pw[k] / ns[k] for k in pw]
    tsales = [ns[k] for k in ns]
    lines_b.append(srow("Tract annual mean price (\\$000s)", [p / 1000 for p in tprice], "{:,.1f}"))
    lines_b.append(srow("Tract annual transactions", tsales, "{:,.1f}"))
    trt = load = list(csv.DictReader(open(os.path.join(D2, "design2_tract_treatment.csv"),
                                          newline="", encoding="utf-8")))
    nev = [f(r["n_events"]) for r in trt if f(r["n_events"])]
    ntracts = len({k[0] for k in pw})
    lines_b.append(srow("Identified purchases (treated tracts)", nev, "{:,.1f}"))

    # ---- Panel C: HMDA long panel -------------------------------------------
    ph, pn, inc = [], [], []
    with open(os.path.join(D2, "hmda_tract_year_long.csv"),
              newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            ph.append(f(r["purch_hisp_n"]) or 0.0)
            pn.append(f(r["purch_nonhisp_n"]) or 0.0)
            ic, icn = f(r["purch_hisp_inc"]) or 0, f(r["purch_hisp_incn"]) or 0
            ic2, icn2 = f(r["purch_nonhisp_inc"]) or 0, f(r["purch_nonhisp_incn"]) or 0
            if icn + icn2 > 0:
                inc.append((ic + ic2) / (icn + icn2))
    lines_c.append(srow("Hispanic-borrower purchases", ph, "{:,.1f}"))
    lines_c.append(srow("Non-Hispanic-borrower purchases", pn, "{:.3f}"))
    lines_c.append(srow("Mean borrower income (\\$000s)", inc, "{:,.1f}"))

    # ---- Panel D: 2010 PRCS -------------------------------------------------
    prcs = list(csv.DictReader(open(os.path.join(D2, "prcs2010_tract_controls.csv"),
                                    newline="", encoding="utf-8")))
    PR = [("med_hh_inc", "Median household income (\\$)", "{:,.0f}"),
          ("med_value", "Median home value (\\$)", "{:,.0f}"),
          ("med_rent", "Median gross rent (\\$)", "{:,.0f}"),
          ("poverty", "Poverty rate", "{:.3f}"),
          ("ba_share", "BA+ share (25+)", "{:.3f}"),
          ("renter_share", "Renter share", "{:.3f}"),
          ("vacancy", "Vacancy rate", "{:.3f}"),
          ("seasonal_share", "Seasonal-home share", "{:.3f}"),
          ("mainland_share", "Born-in-mainland share", "{:.3f}"),
          ("pop", "Population", "{:,.0f}")]
    for c, lab, fmt in PR:
        lines_d.append(srow(lab, [f(r[c]) for r in prcs if f(r[c]) is not None], fmt))

    note = ("This table presents summary statistics for the paper's main "
            "samples. Panel A: market sales within 1km of an identified "
            "decree-era investor purchase (ring design estimation sample: "
            "gap ring, junk/nominal prices, and investor-parcel sales "
            "excluded; events 2012+); name-classification indicators are "
            "defined over sales whose parties' surnames classify. Panel B: "
            "Red Atlas tract$\\times$year panel (transaction-count-weighted "
            "annual mean prices); identified purchases reported over the "
            f"{len(nev)} treated tracts. Panel C: HMDA tract$\\times$year "
            "panel of originated first-lien owner-occupied 1--4 family "
            "purchases, 2012--2024. Panel D: 2010 PRCS tract "
            "characteristics (2020 boundaries, population-weighted).")

    lines = ["\\begin{table}[H]", "\\centering",
             f"\\caption{{\\textbf{{Summary Statistics}} {note}}}",
             "\\scalebox{0.85}{", "\\onehalfspacing",
             "\\begin{tabular}{lcccccc}", "\\toprule\\midrule",
             " & Mean & Std. Dev. & P25 & Median & P75 & Observations \\\\",
             " & (1) & (2) & (3) & (4) & (5) & (6) \\\\", "\\midrule",
             "    \\textbf{Panel A: Ring-design sales ($\\le$1km of an event)} & & & & & & \\\\"]
    lines += lines_a
    lines.append("    \\textbf{Panel B: Tract price panel (Red Atlas)} & & & & & & \\\\")
    lines += lines_b
    lines.append("    \\textbf{Panel C: HMDA purchases (2012--2024)} & & & & & & \\\\")
    lines += lines_c
    lines.append("    \\textbf{Panel D: 2010 PRCS tract characteristics} & & & & & & \\\\")
    lines += lines_d
    lines += ["\\midrule\\bottomrule", "\\end{tabular}", "}",
              "\\label{tab:summary_stats}", "\\end{table}"]
    with open(os.path.join(OUT, "tab_summary_stats.tex"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("wrote tab_summary_stats.tex")


if __name__ == "__main__":
    main()
