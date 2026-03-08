"""
draw_trial.py — Compose a full Ebbinghaus stimulus from a trial row

Takes a single trial row (one-row DataFrame or dict) and returns
a matplotlib Figure ready for display or saving.
"""

import math
import numpy as np
import matplotlib.pyplot as plt

from src.draw_shape import draw_shape


def compute_group_positions(
    orientation: str, canvas_width: int, canvas_height: int
) -> dict:
    """Compute center positions for groups A and B based on orientation."""
    cx = canvas_width / 2
    cy = canvas_height / 2

    if orientation == "horizontal":
        return dict(
            a_x=canvas_width * 0.25, a_y=cy,
            b_x=canvas_width * 0.75, b_y=cy,
        )
    elif orientation == "vertical":
        return dict(
            a_x=cx, a_y=canvas_height * 0.75,
            b_x=cx, b_y=canvas_height * 0.25,
        )
    elif orientation == "diagonal":
        return dict(
            a_x=canvas_width * 0.25, a_y=canvas_height * 0.75,
            b_x=canvas_width * 0.75, b_y=canvas_height * 0.25,
        )
    else:
        raise ValueError(f"Unknown orientation: {orientation}")


def compute_surround_positions(
    cx: float, cy: float, n: int, distance: float
) -> list[tuple[float, float]]:
    """Compute positions for N surround shapes equally spaced around a center."""
    angles = np.linspace(0, 2 * np.pi, n, endpoint=False)
    return [(cx + distance * np.cos(a), cy + distance * np.sin(a)) for a in angles]


def compute_all_extents(trial: dict, positions: dict, padding: float = 0.05) -> dict:
    """Compute bounding box that contains all shapes in a trial."""
    all_x = [
        positions["a_x"] - trial["test_a_size"],
        positions["a_x"] + trial["test_a_size"],
        positions["b_x"] - trial["test_b_size"],
        positions["b_x"] + trial["test_b_size"],
    ]
    all_y = [
        positions["a_y"] - trial["test_a_size"],
        positions["a_y"] + trial["test_a_size"],
        positions["b_y"] - trial["test_b_size"],
        positions["b_y"] + trial["test_b_size"],
    ]

    sa_n = trial.get("surround_a_n", 0)
    if not _is_na(sa_n) and sa_n > 0:
        spos_a = compute_surround_positions(
            positions["a_x"], positions["a_y"],
            int(sa_n), trial["surround_a_distance"],
        )
        for sx, sy in spos_a:
            all_x.extend([sx - trial["surround_a_size"], sx + trial["surround_a_size"]])
            all_y.extend([sy - trial["surround_a_size"], sy + trial["surround_a_size"]])

    sb_n = trial.get("surround_b_n", 0)
    if not _is_na(sb_n) and sb_n > 0:
        spos_b = compute_surround_positions(
            positions["b_x"], positions["b_y"],
            int(sb_n), trial["surround_b_distance"],
        )
        for sx, sy in spos_b:
            all_x.extend([sx - trial["surround_b_size"], sx + trial["surround_b_size"]])
            all_y.extend([sy - trial["surround_b_size"], sy + trial["surround_b_size"]])

    xmin, xmax = min(all_x), max(all_x)
    ymin, ymax = min(all_y), max(all_y)
    x_pad = (xmax - xmin) * padding
    y_pad = (ymax - ymin) * padding

    return dict(
        xmin=xmin - x_pad, xmax=xmax + x_pad,
        ymin=ymin - y_pad, ymax=ymax + y_pad,
    )


def _is_na(val) -> bool:
    """Check if a value is NaN/None."""
    if val is None:
        return True
    try:
        return math.isnan(val)
    except (TypeError, ValueError):
        return False


def draw_trial(trial) -> plt.Figure:
    """Draw a complete Ebbinghaus stimulus from trial parameters.

    Args:
        trial: A one-row DataFrame or dict with the trials table schema.

    Returns:
        A matplotlib Figure.
    """
    if hasattr(trial, "iloc"):
        assert len(trial) == 1
        trial = trial.iloc[0].to_dict()

    positions = compute_group_positions(
        trial["orientation"], trial["canvas_width"], trial["canvas_height"]
    )
    extents = compute_all_extents(trial, positions)

    # Figure size in inches (96 dpi)
    w_in = trial["canvas_width"] / 96
    h_in = trial["canvas_height"] / 96
    fig, ax = plt.subplots(1, 1, figsize=(w_in, h_in))
    fig.patch.set_facecolor(trial["background_color"])
    ax.set_facecolor(trial["background_color"])

    ax.set_xlim(extents["xmin"], extents["xmax"])
    ax.set_ylim(extents["ymin"], extents["ymax"])
    ax.set_aspect("equal")
    ax.axis("off")

    # Draw surround shapes (behind test shapes)
    sa_n = trial.get("surround_a_n", 0)
    if not _is_na(sa_n) and sa_n > 0:
        spos_a = compute_surround_positions(
            positions["a_x"], positions["a_y"],
            int(sa_n), trial["surround_a_distance"],
        )
        for sx, sy in spos_a:
            draw_shape(
                ax, trial["surround_a_shape"], sx, sy,
                trial["surround_a_size"],
                color=trial["surround_a_color"],
                fill=trial["surround_a_fill"] if not _is_na(trial.get("surround_a_fill")) else None,
            )

    sb_n = trial.get("surround_b_n", 0)
    if not _is_na(sb_n) and sb_n > 0:
        spos_b = compute_surround_positions(
            positions["b_x"], positions["b_y"],
            int(sb_n), trial["surround_b_distance"],
        )
        for sx, sy in spos_b:
            draw_shape(
                ax, trial["surround_b_shape"], sx, sy,
                trial["surround_b_size"],
                color=trial["surround_b_color"],
                fill=trial["surround_b_fill"] if not _is_na(trial.get("surround_b_fill")) else None,
            )

    # Draw test shapes (on top)
    draw_shape(
        ax, trial["test_a_shape"],
        positions["a_x"], positions["a_y"],
        trial["test_a_size"],
        color=trial["test_a_color"],
        fill=trial["test_a_fill"] if not _is_na(trial.get("test_a_fill")) else None,
    )
    draw_shape(
        ax, trial["test_b_shape"],
        positions["b_x"], positions["b_y"],
        trial["test_b_size"],
        color=trial["test_b_color"],
        fill=trial["test_b_fill"] if not _is_na(trial.get("test_b_fill")) else None,
    )

    fig.subplots_adjust(left=0, right=1, top=1, bottom=0)
    return fig
