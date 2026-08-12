"""Event-study figure for the zip-level outmigration DiD (base spec).

Reads output/experian/zip_migration_coefs.csv (lpdid event matrices) and plots
the any-zip-move base spec (T_any_base): coefficients + 95% CI by event time,
reference period t-1. Companion off-island panel included for context.

Output: output/experian/fig_es_outmigration.png
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

OUT = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise\output\experian"
df = pd.read_csv(os.path.join(OUT, "zip_migration_coefs.csv"))
ev = df[df["matrix_type"] == "event"].copy()

TIME = {"pre4": -4, "pre3": -3, "pre2": -2, "pre1": -1,
        "tau0": 0, "tau1": 1, "tau2": 2, "tau3": 3}

INK = "#374151"
MUTED = "#9ca3af"
BLUE = "#2563eb"

def panel(ax, tag, title):
    s = ev[ev["test"] == tag].copy()
    s["t"] = s["rowname"].map(TIME)
    s = s.sort_values("t")
    ax.axhline(0, color=MUTED, lw=1, zorder=1)
    ax.axvline(-0.5, color=MUTED, lw=1, ls=":", zorder=1)
    ax.errorbar(s["t"], s["c1"], yerr=[s["c1"] - s["c5"], s["c6"] - s["c1"]],
                fmt="o", color=BLUE, ecolor=BLUE, elinewidth=2, capsize=3,
                ms=7, zorder=3)
    ref = s[s["t"] == -1]
    ax.plot(ref["t"], ref["c1"], "o", ms=7, mfc="white", mec=BLUE, mew=2, zorder=4)
    ax.set_title(title, fontsize=11, color=INK, loc="left")
    ax.set_xlabel("Years since first investor purchase in zip", fontsize=9, color=INK)
    ax.set_xticks(range(-4, 4))
    ax.tick_params(colors=INK, labelsize=9)
    ax.grid(axis="y", color="#e5e7eb", lw=0.8, zorder=0)
    for sp in ["top", "right"]:
        ax.spines[sp].set_visible(False)
    for sp in ["left", "bottom"]:
        ax.spines[sp].set_color(MUTED)

fig, axes = plt.subplots(1, 2, figsize=(10, 4.2), sharex=True)
panel(axes[0], "T_any_base", "Moved to any different zip (pp)")
panel(axes[1], "T_offpr_base", "Moved off-island (pp)")
axes[0].set_ylabel("Effect on outmigration rate, pp\n(95% CI, ref. year \u22121)",
                   fontsize=9, color=INK)
fig.suptitle("Outmigration event study, zip-level lpdid (base spec, 132 PR ZCTAs, 2005\u20132022)",
             fontsize=12, color=INK, x=0.01, ha="left")
fig.tight_layout(rect=[0, 0, 1, 0.94])
p = os.path.join(OUT, "fig_es_outmigration.png")
fig.savefig(p, dpi=200, facecolor="white")
print("saved", p)
