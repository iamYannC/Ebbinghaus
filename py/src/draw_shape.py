"""
draw_shape.py — Atomic shape-drawing function

Draws a single shape as a matplotlib patch. Knows nothing about trials, the
Ebbinghaus illusion, or experimental design.
"""

import matplotlib.patches as mpatches
import numpy as np


def draw_shape(
    ax,
    shape: str,
    x: float,
    y: float,
    size: float,
    color: str = "black",
    fill=None,
    alpha: float = 1.0,
):
    """Draw a single shape on a matplotlib Axes.

    Args:
        ax: matplotlib Axes to draw on.
        shape: "circle" or "square".
        x: Center x-coordinate.
        y: Center y-coordinate.
        size: Radius (circle) or half side-length (square), in plot units.
        color: Border/stroke color.
        fill: Fill color. None = no fill (transparent).
        alpha: Opacity (0-1).
    """
    assert shape in ("circle", "square"), f"Unknown shape: {shape}"
    assert size > 0

    facecolor = fill if fill is not None else "none"

    if shape == "circle":
        patch = mpatches.Circle(
            (x, y), radius=size,
            edgecolor=color, facecolor=facecolor, alpha=alpha, linewidth=1,
        )
    elif shape == "square":
        patch = mpatches.Rectangle(
            (x - size, y - size), width=2 * size, height=2 * size,
            edgecolor=color, facecolor=facecolor, alpha=alpha, linewidth=1,
        )

    ax.add_patch(patch)
