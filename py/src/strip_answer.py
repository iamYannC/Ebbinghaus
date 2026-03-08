"""
strip_answer.py — Strip ground-truth answer from image filenames

Image files are saved as <id>_<true_larger>_t<tier>.<ext> for researcher convenience.
Before sending images to AI models, use these functions to produce clean
copies or paths that don't leak the answer.
"""

import os
import re
import shutil
import pandas as pd


def strip_answer_from_path(path: str) -> str:
    """Strip the answer and tier from a single file path.

    Converts "images/42_equal_t1.png" -> "images/42.png"
    Also handles the old format without tier.

    Args:
        path: File path in the format <id>_<answer>_t<tier>.<ext>

    Returns:
        Cleaned path in the format <id>.<ext>
    """
    return re.sub(
        r"^(.+[/\\]\d+)_(equal|a|b)(_t[0-9NA]+)?(\.[a-z]+)$",
        r"\1\4",
        path,
    )


def strip_answer_from_images(
    trials: pd.DataFrame,
    output_dir: str = "images_eval",
    verbose: bool = True,
) -> pd.DataFrame:
    """Create answer-stripped copies of image files for AI evaluation.

    Copies each image to a clean filename (without the ground-truth answer)
    in a target directory.

    Args:
        trials: DataFrame with trials schema (needs `file_path` column).
        output_dir: Directory for the stripped copies.
        verbose: Print progress.

    Returns:
        The input DataFrame with `file_path` updated to the
        stripped copies. Original path preserved in `file_path_original`.
    """
    os.makedirs(output_dir, exist_ok=True)

    trials = trials.copy()
    trials["file_path_original"] = trials["file_path"]
    trials["file_path"] = [
        os.path.join(output_dir, os.path.basename(strip_answer_from_path(p)))
        for p in trials["file_path"]
    ]

    for i in range(len(trials)):
        src = trials.iloc[i]["file_path_original"]
        dst = trials.iloc[i]["file_path"]

        if not os.path.exists(src):
            print(f"WARNING: Source file not found: {src}")
            continue

        shutil.copy2(src, dst)

    if verbose:
        print(
            f"Copied {len(trials)} images to {output_dir} "
            "with answer-stripped filenames."
        )

    return trials
