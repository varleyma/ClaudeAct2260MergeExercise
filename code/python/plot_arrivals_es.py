"""Single-graph event-study figures for the investor-begets-investor
arrivals DiD (one graph per file, user rule 2026-11-03).

Reads output/design1/arrivals_coefs.csv (lpdid matrices from
design1_arrivals_did.do); 0-250m and 250-500m rings vs 1500-2000m control.

Outputs (output/design1/):
    fig_arrivals_es_all.png/.pdf    all 1,160 decree-era events
    fig_arrivals_es_first.png/.pdf  237 first-investor events (no investor
                                    within 1 km at purchase; pre ~ 0 by def.)
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

OUT = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise\output\design1"
df = pd.read_csv(os.path.join(OUT, "arrivals_coefs.csv"))
ev = df[df["matrix_type"] == "event"].copy()

TIME = {"pre4": -4, "pre3": -3, "pre2": -2, "pre1": -1,
        "tau0": 0, "tau1": 1, "tau2": 2, "tau3": 3}

INK = "#374151"
MUTED = "#9ca3af"
BLUE = "#2563eb"
ORANGE = "#d97706"


def series(ax, tag, color, off, label):
    s = ev[ev["test"] == tag].copy()
    s["t"] = s["rowname"].map(TIME)
    s = s.dropna(subset=["t"]).sort_values("t")
    ax.errorbar(s["t"] + off, s["c1"], yerr=[s["c1"] - s["c5"], s["c6"] - s["c1"]],
                fmt="o", color=color, ecolor=color, elinewidth=1.8, capsize=3,
                ms=6, zorder=3, label=label)
    ref = s[s["t"] == -1]
    ax.plot(ref["t"] + off, ref["c1"], "o", ms=6, mfc="white", mec=color, mew=1.8, zorder=4)


def make(samp, title, stem):
    fig, ax = plt.subplots(figsize=(6.8, 4.6))
    ax.axhline(0, color=MUTED, lw=1, zorder=1)
    ax.axvline(-0.5, color=MUTED, lw=1, ls=":", zorder=1)
    series(ax, f"A_0_250_{samp}", BLUE, -0.08, "0\u2013250 m ring")
    series(ax, f"A_250_500_{samp}", ORANGE, 0.08, "250\u2013500 m ring")
    ax.set_title(title, fontsize=11, color=INK, loc="left")
    ax.set_xlabel("Years since investor purchase", fontsize=9, color=INK)
    ax.set_ylabel("Other-investor arrivals per km\u00b2 per year,\nvs 1500\u20132000 m control band (95% CI, ref. t\u22121)",
                  fontsize=9, color=INK)
    ax.set_xticks(range(-4, 4))
    ax.legend(frameon=False, fontsize=9, labelcolor=INK, loc="upper left")
    ax.tick_params(colors=INK, labelsize=9)
    ax.grid(axis="y", color="#e5e7eb", lw=0.8, zorder=0)
    for sp in ["top", "right"]:
        ax.spines[sp].set_visible(False)
    for sp in ["left", "bottom"]:
        ax.spines[sp].set_color(MUTED)
    fig.tight_layout()
    for ext in ("png", "pdf"):
        p = os.path.join(OUT, f"{stem}.{ext}")
        fig.savefig(p, dpi=200, facecolor="white")
        print("saved", p)
    plt.close(fig)


make("all", "Other-investor arrivals around an investor purchase:\nall decree-era events (n=1,160), lpdid",
     "fig_arrivals_es_all")
make("first", "Other-investor arrivals around a FIRST investor purchase\n(n=237, no investor within 1 km at purchase; pre \u2248 0 by definition)",
     "fig_arrivals_es_first")
