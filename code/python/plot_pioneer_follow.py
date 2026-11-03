"""Figure: once the first investor arrives, how likely is it that others follow?

Reads output/design1/pioneer_follow_coefs.csv (design1_pioneer_follow.do).
Panel A: raw cumulative incidence of >=1 subsequent other-investor arrival
within 500m by horizon, pioneers vs virgin luxury controls. Panel B: the
regression-adjusted difference (LPM with year + municipio FE, cluster muni)
in percentage points by radius and horizon, 95% CI.

Output: output/design1/fig_pioneer_follow.png / .pdf
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

OUT = r"C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise\output\design1"
df = pd.read_csv(os.path.join(OUT, "pioneer_follow_coefs.csv"))
lpm = df[df["est"] == "lpm"].copy()

INK = "#374151"
MUTED = "#9ca3af"
BLUE = "#2563eb"
LIGHTBLUE = "#93c5fd"
ORANGE = "#d97706"
GRAY = "#6b7280"

fig, axes = plt.subplots(1, 2, figsize=(10, 4.4))

# ---- Panel A: cumulative incidence at 500m ----
ax = axes[0]
s = lpm[lpm["radius"] == 500].sort_values("horizon")
h = [0] + list(s["horizon"])
ax.plot(h, [0] + list(100 * s["mean_pio"]), color=BLUE, lw=2.2, marker="o", ms=6,
        label="After a pioneer investor purchase")
ax.plot(h, [0] + list(100 * s["mean_ctl"]), color=GRAY, lw=2.0, marker="s", ms=5,
        label="After a virgin luxury purchase\n(same price band, no investor within 1 km)")
for x, y in zip(s["horizon"], 100 * s["mean_pio"]):
    ax.annotate(f"{y:.0f}%", (x, y), textcoords="offset points", xytext=(0, 7),
                ha="center", fontsize=9, color=BLUE, fontweight="bold")
for x, y in zip(s["horizon"], 100 * s["mean_ctl"]):
    ax.annotate(f"{y:.0f}%", (x, y), textcoords="offset points", xytext=(0, -14),
                ha="center", fontsize=9, color=GRAY)
ax.set_title("A. P(\u22651 other decree investor arrives\nwithin 500 m by year k)", fontsize=11, color=INK, loc="left")
ax.set_xlabel("Years since purchase (k)", fontsize=9, color=INK)
ax.set_ylabel("Percent of sites", fontsize=9, color=INK)
ax.set_xticks([0, 1, 2, 3])
ax.set_ylim(bottom=0)
ax.legend(frameon=False, fontsize=8.5, labelcolor=INK, loc="upper left")
ax.tick_params(colors=INK, labelsize=9)
ax.grid(axis="y", color="#e5e7eb", lw=0.8, zorder=0)
for sp in ["top", "right"]:
    ax.spines[sp].set_visible(False)
for sp in ["left", "bottom"]:
    ax.spines[sp].set_color(MUTED)

# ---- Panel B: adjusted differences ----
ax = axes[1]
ax.axhline(0, color=MUTED, lw=1, zorder=1)
offs = {250: -0.18, 500: 0.0, 1000: 0.18}
colors = {250: GRAY, 500: ORANGE, 1000: BLUE}
labels = {250: "within 250 m", 500: "within 500 m", 1000: "within 1 km"}
for r in (250, 500, 1000):
    s = lpm[lpm["radius"] == r].sort_values("horizon")
    ax.errorbar(s["horizon"] + offs[r], 100 * s["coef"], yerr=100 * 1.96 * s["se"],
                fmt="o", color=colors[r], ecolor=colors[r], elinewidth=1.8,
                capsize=3, ms=6, zorder=3, label=labels[r])
ax.set_title("B. Adjusted difference, pioneer \u2212 control\n(year + municipio FE, 95% CI)", fontsize=11, color=INK, loc="left")
ax.set_xlabel("Years since purchase (k)", fontsize=9, color=INK)
ax.set_ylabel("Percentage points", fontsize=9, color=INK)
ax.set_xticks([1, 2, 3])
ax.legend(frameon=False, fontsize=9, labelcolor=INK, loc="upper left")
ax.tick_params(colors=INK, labelsize=9)
ax.grid(axis="y", color="#e5e7eb", lw=0.8, zorder=0)
for sp in ["top", "right"]:
    ax.spines[sp].set_visible(False)
for sp in ["left", "bottom"]:
    ax.spines[sp].set_color(MUTED)

fig.suptitle("Once the first investor arrives, others follow (237 pioneer events vs 11,367 virgin luxury purchases)",
             fontsize=12, color=INK, x=0.01, ha="left")
fig.tight_layout(rect=[0, 0, 1, 0.93])
for ext in ("png", "pdf"):
    p = os.path.join(OUT, f"fig_pioneer_follow.{ext}")
    fig.savefig(p, dpi=200, facecolor="white")
    print("saved", p)
