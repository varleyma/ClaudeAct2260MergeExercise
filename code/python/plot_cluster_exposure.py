"""Two-panel descriptive figure: buyer exposure to decree investors + investor
clustering vs the island-wide luxury benchmark.

Reads data/design1/exposure_by_year.csv and clustering_summary.csv
(build_exposure_clustering.py). Panel A: share of market homebuyers (individual
non-corporate buyers, non-investor parcels, price >= $10k) with at least one
prior decree-investor purchase within d at the time they bought. Panel B:
probability a prior decree investor (different buyer) is within d at purchase,
investor events vs luxury-band purchases reweighted to the investor year mix.

Output: output/design1/fig_cluster_exposure.png / .pdf
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

ey = pd.read_csv(os.path.join(D1, "exposure_by_year.csv"))
cs = pd.read_csv(os.path.join(D1, "clustering_summary.csv"))

# ---------- Panel A: market-buyer exposure by year ----------
mk = ey[ey["group"] == "market_individual"].sort_values("year")
fig, axes = plt.subplots(1, 2, figsize=(10, 4.4))
ax = axes[0]
for col, color, lw, label in [
        ("sh1000", BLUE, 2.2, "within 1 km"),
        ("sh500", ORANGE, 2.0, "within 500 m"),
        ("sh250", GRAY, 1.8, "within 250 m")]:
    ax.plot(mk["year"], 100 * mk[col], color=color, lw=lw, marker="o", ms=4, label=label)
ax.set_title("A. Share of homebuyers with a decree investor\nalready nearby when they bought", fontsize=11, color=INK, loc="left")
ax.set_ylabel("Percent of market purchases", fontsize=9, color=INK)
ax.set_xlabel("Year of purchase", fontsize=9, color=INK)
ax.set_xticks(range(2012, 2026, 2))
ax.set_ylim(bottom=0)
ax.legend(frameon=False, fontsize=9, labelcolor=INK, loc="upper left")
ax.tick_params(colors=INK, labelsize=9)
ax.grid(axis="y", color="#e5e7eb", lw=0.8, zorder=0)
for sp in ["top", "right"]:
    ax.spines[sp].set_visible(False)
for sp in ["left", "bottom"]:
    ax.spines[sp].set_color(MUTED)

# ---------- Panel B: investor clustering vs luxury benchmark ----------
ax = axes[1]
cs = cs.sort_values("radius_m")
x = range(len(cs))
wd = 0.38
b1 = ax.bar([i - wd / 2 for i in x], 100 * cs["p_investor"], wd,
            color=BLUE, label="Decree-investor purchases", zorder=3)
b2 = ax.bar([i + wd / 2 for i in x], 100 * cs["p_luxury_yearadj"], wd,
            color=LIGHTBLUE, label="Luxury benchmark\n(same price band, year-adj.)", zorder=3)
for i, (pi, pl, ratio) in enumerate(zip(cs["p_investor"], cs["p_luxury_yearadj"],
                                        cs["ratio_vs_luxury"])):
    ax.annotate(f"\u00d7{ratio:.1f}", (i - wd / 2, 100 * pi), textcoords="offset points",
                xytext=(0, 4), ha="center", fontsize=9, color=INK, fontweight="bold")
ax.set_title("B. Another decree investor already within d\nat time of purchase", fontsize=11, color=INK, loc="left")
ax.set_ylabel("Percent of purchases", fontsize=9, color=INK)
ax.set_xlabel("Distance d", fontsize=9, color=INK)
ax.set_xticks(list(x))
ax.set_xticklabels([f"{int(r)} m" if r < 1000 else f"{r/1000:g} km" for r in cs["radius_m"]])
ax.set_ylim(0, 118)
ax.set_yticks(range(0, 101, 20))
ax.legend(frameon=False, fontsize=8, labelcolor=INK, loc="upper left")
ax.tick_params(colors=INK, labelsize=9)
ax.grid(axis="y", color="#e5e7eb", lw=0.8, zorder=0)
for sp in ["top", "right"]:
    ax.spines[sp].set_visible(False)
for sp in ["left", "bottom"]:
    ax.spines[sp].set_color(MUTED)

fig.suptitle("Decree investors cluster: buyer exposure and investor co-location (CRIM island snapshot, 2012\u20132025)",
             fontsize=12, color=INK, x=0.01, ha="left")
fig.tight_layout(rect=[0, 0, 1, 0.93])
for ext in ("png", "pdf"):
    p = os.path.join(OUT, f"fig_cluster_exposure.{ext}")
    fig.savefig(p, dpi=200, facecolor="white")
    print("saved", p)
