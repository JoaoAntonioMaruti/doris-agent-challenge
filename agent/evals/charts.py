"""Latency chart for the README, built from the latest E2E reports.

    docker run --rm -v "$PWD/agent:/agent" -w /agent python:3.11-slim \
      sh -c "pip install -q matplotlib && python evals/charts.py"
"""
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

ROOT = Path(__file__).resolve().parent
OUT = ROOT.parent / "docs" / "latency.png"

SURFACE, INK, MUTED, GRID = "#1a1a19", "#f0efec", "#c3c2b7", "#383835"
COLORS = {"scenarios": "#3987e5", "faults": "#d95926"}
LABELS = {"scenarios": "Cenários do desafio", "faults": "Testes de falha"}


def turns(suite):
    report = json.loads((ROOT / "reports" / f"{suite}-latest.json").read_text())
    rows = []
    for sc in report["scenarios"]:
        many = len(sc["turns"]) > 1
        for i, t in enumerate(sc["turns"], 1):
            name = sc["id"].split("_", 1)[0] + (f" · turno {i}" if many else "")
            rows.append((name, sc["title"], t["latency_ms"] / 1000, suite))
    return rows


def main():
    rows = turns("scenarios") + turns("faults")
    rows.reverse()  # first scenario on top

    fig, ax = plt.subplots(figsize=(10, 0.42 * len(rows) + 1.6), dpi=200)
    fig.patch.set_facecolor(SURFACE)
    ax.set_facecolor(SURFACE)

    y = range(len(rows))
    ax.barh(y, [r[2] for r in rows], height=0.62, color=[COLORS[r[3]] for r in rows],
            edgecolor=SURFACE, linewidth=2)
    ax.set_yticks(list(y), [f"{r[0]}  {r[1]}" for r in rows], color=INK, fontsize=8)

    for i, r in enumerate(rows):
        ax.text(r[2] + 1, i, f"{r[2]:.1f} s", va="center", color=MUTED, fontsize=7.5)

    for x, label in [(80, "deadline interno 80 s"), (100, "corte do proxy 100 s")]:
        ax.axvline(x, color=MUTED, linestyle=(0, (4, 3)), linewidth=1)
        ax.text(x, len(rows) - 0.3, label, color=MUTED, fontsize=7.5, ha="right", va="bottom", rotation=0)

    ax.set_xlim(0, 108)
    ax.set_ylim(-0.6, len(rows) + 0.4)
    ax.set_xlabel("Latência do turno (s)", color=MUTED, fontsize=8.5)
    ax.tick_params(axis="x", colors=MUTED, labelsize=8)
    ax.tick_params(axis="y", length=0)
    ax.grid(axis="x", color=GRID, linewidth=0.6)
    ax.set_axisbelow(True)
    for side in ["top", "right", "left"]:
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_color(GRID)

    handles = [plt.Rectangle((0, 0), 1, 1, color=COLORS[k]) for k in COLORS]
    legend = ax.legend(handles, [LABELS[k] for k in COLORS], loc="lower left", bbox_to_anchor=(0, 1.0),
                       ncol=2, frameon=False, fontsize=8)
    for text in legend.get_texts():
        text.set_color(INK)

    ax.set_title("Quanto cada turno levou, contra os limites de tempo", color=INK, fontsize=11, loc="left", pad=26)
    fig.tight_layout()
    fig.savefig(OUT, facecolor=SURFACE)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
