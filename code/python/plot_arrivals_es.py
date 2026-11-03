"""Event-study figure for the investor-begets-investor arrivals DiD.

Reads output/design1/arrivals_coefs.csv (lpdid matrices from
design1_arrivals_did.do) and plots the 0-250m and 250-500m rings vs the
1500-2000m control band: all events (left) and pioneer4 events -- no other
investor within 1km before t-4, predetermined w.r.t. the pre-window (right).

Output: output/design1/fig_arrivals_es.png / .pdf
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


def panel(ax, samp, title):
    ax.axhline(0, color=MUTED, lw=1, zorder=1)
    ax.axvline(-0.5, color=MUTED, lw=1, ls=":", zorder=1)
    series(ax, f"A_0_250_{samp}", BLUE, -0.08, "0\u2013250 m ring")
    series(ax, f"A_250_500_{samp}", ORANGE, 0.08, "250\u2013500 m ring")
    ax.set_title(title, fontsize=11, color=INK, loc="left")
    ax.set_xlabel("Years since investor purchase", fontsize=9, color=INK)
    ax.set_xticks(range(-4, 4))
    ax.tick_params(colors=INK, labelsize=9)
    ax.grid(axis="y", color="#e5e7eb", lw=0.8, zorder=0)
    for sp in ["top", "right"]:
        ax.spines[sp].set_visible(False)
    for sp in ["left", "bottom"]:
        ax.spines[sp].set_color(MUTED)


fig, axes = plt.subplots(1, 2, figsize=(10, 4.4))
panel(axes[0], "all", "A. All events (n=1,160)")
panel(axes[1], "first", "B. First-investor events (n=237): no investor\nwithin 1 km at purchase (pre \u2248 0 by definition)")
axes[0].set_ylabel("Other-investor arrivals per km\u00b2 per year,\nvs 1500\u20132000 m control band (95% CI, ref. t\u22121)",
                   fontsize=9, color=INK)
axes[0].legend(frameon=False, fontsize=9, labelcolor=INK, loc="upper left")
fig.suptitle("Investor purchases attract more investors: arrivals event study (lpdid, design1 events 2012\u20132025)",
             fontsize=12, color=INK, x=0.01, ha="left")
fig.tight_layout(rect=[0, 0, 1, 0.93])
for ext in ("png", "pdf"):
    p = os.path.join(OUT, f"fig_arrivals_es.{ext}")
    fig.savefig(p, dpi=200, facecolor="white")
    print("saved", p)
