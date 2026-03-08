"""
render_stimuli.py — Batch renderer

Takes a trial DataFrame (or any subset) and renders each row to an image.
"""

import os
import pandas as pd
import matplotlib.pyplot as plt

from src.draw_trial import draw_trial


def render_stimuli(trials: pd.DataFrame, verbose: bool = True) -> pd.DataFrame:
    """Render stimulus images for a trial table.

    Args:
        trials: DataFrame with the trials table schema (or a subset).
        verbose: Print progress messages.

    Returns:
        The input trials DataFrame (unchanged). Side effect: writes
        image files to paths specified in each row's `file_path` column.
    """
    assert isinstance(trials, pd.DataFrame) and len(trials) > 0

    # Ensure output directories exist
    dirs = trials["file_path"].apply(os.path.dirname).unique()
    for d in dirs:
        os.makedirs(d, exist_ok=True)

    n = len(trials)
    errors = []

    for i in range(n):
        row = trials.iloc[i]
        fpath = row["file_path"]
        fmt = row["file_format"]
        w = row["canvas_width"]
        h = row["canvas_height"]

        if verbose and (i % 10 == 0 or i == 0 or i == n - 1):
            print(f"[{i + 1}/{n}] Rendering trial {row['trial_id']} -> {fpath}")

        try:
            fig = draw_trial(row.to_frame().T)

            if fmt == "png":
                fig.savefig(fpath, dpi=96, facecolor=fig.get_facecolor())
            elif fmt == "svg":
                fig.savefig(fpath, format="svg", facecolor=fig.get_facecolor())
            elif fmt == "webp":
                fig.savefig(fpath, format="webp", dpi=96, facecolor=fig.get_facecolor())
            else:
                raise ValueError(f"Unsupported file format: {fmt}")

            plt.close(fig)

            if not os.path.exists(fpath):
                errors.append(f"Trial {row['trial_id']}: file not created")

        except Exception as e:
            errors.append(f"Trial {row['trial_id']}: {e}")
            if verbose:
                print(f"  ERROR: {e}")

    if errors:
        print(f"WARNING: {len(errors)} errors during rendering:")
        for err in errors:
            print(f"  - {err}")
    elif verbose:
        print(f"All {n} stimuli rendered successfully.")

    return trials
