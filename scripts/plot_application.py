#!/usr/bin/env python3
"""Application view from the checked simulation logs: where the paddle is sent after each
window, guard on (s2) vs guard off (s3), same stimulus. Output docs/application_guard.png."""
import json
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

R = Path(__file__).resolve().parent.parent
V = R / "build/sim/vec"
F = json.loads((R / "docs/facts.json").read_text())
W = F["design"]["sim_window_cycles"]
TRUTH = F["truth_intercept_x"]
SURF, INK, INK2, MUTED, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#898781", "#e1e0d9"
BLUE, ORANGE = "#2a78d6", "#eb6834"

def commands(name):
    pts = []
    for line in (V / f"{name}.got").read_text().splitlines():
        p = line.split()
        if p[0] == "CMD":
            tick, x, lat = int(p[1]), int(p[2]), int(p[3])
            pts.append(((tick - lat + 1) // W, x))       # window that produced the command
    return pts

on, off = commands("s2_burst_guard"), commands("s3_burst_noguard")
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 13})
fig, ax = plt.subplots(figsize=(13, 6.2), dpi=150, facecolor=SURF)
ax.set_facecolor(SURF)
ax.axvspan(11.5, 21.5, color="#f0efea", zorder=0)
ax.text(16.5, 632, "background burst: 900 extra events per window", ha="center", va="top",
        color=INK2, fontsize=12)
ax.axhline(TRUTH, color=MUTED, lw=1.5, ls=(0, (5, 4)), zorder=1)
ax.text(36.6, TRUTH + 10, f"true crossing x = {TRUTH:.0f} px", ha="right", va="bottom", color=INK2, fontsize=12)
for pts, col, lab in [(off, ORANGE, "guard off"), (on, BLUE, "guard on")]:
    xs, ys = zip(*pts)
    ax.plot(xs, ys, color=col, lw=2, zorder=3, label=lab, solid_capstyle="round")
    ax.scatter(xs, ys, s=64, color=col, edgecolor=SURF, linewidth=2, zorder=4)
wo = max(off, key=lambda p: abs(p[1] - TRUTH))
ax.annotate(f"guard off: {wo[1]} px", xy=wo, xytext=(wo[0] + 0.5, wo[1] - 26), color=INK, fontsize=12, va="center")
ax.set_xlim(3.5, 37)
ax.set_ylim(0, 640)
ax.set_yticks([0, 160, 320, 480, 640])
ax.set_xlabel(f"window ({W} cycles = 20 µs each at 100 MHz)", color=INK2)
ax.set_ylabel("paddle command: predicted x (px)", color=INK2)
ax.grid(axis="y", color=GRID, lw=1)
for s in ["top", "right", "left"]:
    ax.spines[s].set_visible(False)
ax.spines["bottom"].set_color(MUTED)
ax.tick_params(colors=INK2, length=0)
ax.legend(loc="lower left", frameon=False, fontsize=12, labelcolor=INK)
ax.set_title("Where the paddle is sent after each window (simulated, same input both runs)",
             loc="left", color=INK, fontsize=15, pad=14)
fig.tight_layout()
fig.savefig(R / "docs/application_guard.png", facecolor=SURF)
print("worst guard-off", wo, "| guard-on range", min(y for _, y in on[3:]), max(y for _, y in on[3:]))
