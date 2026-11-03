"""Single-graph figures: buyer exposure to decree investors + investor
clustering vs the island-wide luxury benchmark (one graph per file, user
rule 2026-11-03).

Reads data/design1/exposure_by_year.csv and clustering_summary.csv
(build_exposure_clustering.py).

Outputs (output/design1/):
    fig_exposure_by_year.png/.pdf      share of market homebuyers with a
                                       prior decree investor nearby, by year
    fig_clustering_vs_luxury.png/.pdf  P(prior investor within d) at purchase,
                                       investor events vs luxury benchmark
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

REPO = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise"
D1 = os.path.join(REPO, "data", "design1")
OUT = os.path.join(REPO, "output", "design1")

INK = "#374151"
MUTED = "#9ca3af"
BLUE = "#2563eb"
LIGHTBLUE = "#93c5fd"
ORANGE = "#d97706"
GRAY = "#6b7280"


def style(ax):
    ax.tick_params(colors=INK, labelsize=9)
    ax.grid(axis="y", color="#e5e7eb", lw=0.8, zorder=0)
    for sp in ["top", "right"]:
        ax.spines[sp].set_visible(False)
    for sp in ["left", "bottom"]:
        ax.spines[sp].set_color(MUTED)


def save(fig, stem):
    fig.tight_layout()
    for ext in ("png", "pdf"):
        p = os.path.join(OUT, f"{stem}.{ext}")
        fig.savefig(p, dpi=200, facecolor="white")
        print("saved", p)
    plt.close(fig)


ey = pd.read_csv(os.path.join(D1, "exposure_by_year.csv"))
cs = pd.read_csv(os.path.join(D1, "clustering_summary.csv"))

# ---------- Figure 1: market-buyer exposure by year ----------
mk = ey[ey["group"] == "market_individual"].sort_values("year")
fig, ax = plt.subplots(figsize=(6.8, 4.6))
for col, color, lw, label in [
        ("sh1000", BLUE, 2.2, "within 1 km"),
        ("sh500", ORANGE, 2.0, "within 500 m"),
        ("sh250", GRAY, 1.8, "within 250 m")]:
    ax.plot(mk["year"], 100 * mk[col], color=color, lw=lw, marker="o", ms=4, label=label)
ax.set_title("Share of PR homebuyers with a decree investor already nearby\nwhen they bought (CRIM island snapshot, market purchases)",
             fontsize=11, color=INK, loc="left")
ax.set_ylabel("Percent of market purchases", fontsize=9, color=INK)
ax.set_xlabel("Year of purchase", fontsize=9, color=INK)
ax.set_xticks(range(2012, 2026, 2))
ax.set_ylim(bottom=0)
ax.legend(frameon=False, fontsize=9, labelcolor=INK, loc="upper left")
style(ax)
save(fig, "fig_exposure_by_year")

# ---------- Figure 2: investor clustering vs luxury benchmark ----------
cs = cs.sort_values("radius_m")
fig, ax = plt.subplots(figsize=(6.8, 4.6))
x = range(len(cs))
wd = 0.38
ax.bar([i - wd / 2 for i in x], 100 * cs["p_investor"], wd,
       color=BLUE, label="Decree-investor purchases", zorder=3)
ax.bar([i + wd / 2 for i in x], 100 * cs["p_luxury_yearadj"], wd,
       color=LIGHTBLUE, label="Luxury benchmark\n(same price band, year-adj.)", zorder=3)
for i, (pi, ratio) in enumerate(zip(cs["p_investor"], cs["ratio_vs_luxury"])):
    ax.annotate(f"\u00d7{ratio:.1f}", (i - wd / 2, 100 * pi), textcoords="offset points",
                xytext=(0, 4), ha="center", fontsize=9, color=INK, fontweight="bold")
ax.set_title("Another decree investor already within d at time of purchase:\ninvestors vs island-wide luxury benchmark, 2012\u20132025",
             fontsize=11, color=INK, loc="left")
ax.set_ylabel("Percent of purchases", fontsize=9, color=INK)
ax.set_xlabel("Distance d", fontsize=9, color=INK)
ax.set_xticks(list(x))
ax.set_xticklabels([f"{int(r)} m" if r < 1000 else f"{r/1000:g} km" for r in cs["radius_m"]])
ax.set_ylim(0, 118)
ax.set_yticks(range(0, 101, 20))
ax.legend(frameon=False, fontsize=8.5, labelcolor=INK, loc="upper left")
style(ax)
save(fig, "fig_clustering_vs_luxury")
