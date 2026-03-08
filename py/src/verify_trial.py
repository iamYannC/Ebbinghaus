"""
verify_trial.py — Deterministic ground-truth verifier

Pure function. No side effects. Does not read images.
Takes trial parameters, returns ground truth columns.
"""

import numpy as np
import pandas as pd

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from config.defaults import FLOAT_TOLERANCE


def verify_trial(trials: pd.DataFrame, tol: float = FLOAT_TOLERANCE) -> pd.DataFrame:
    """Compute ground truth for trial(s).

    Args:
        trials: DataFrame with at least `test_a_size` and `test_b_size`.
        tol: Floating-point tolerance for equality.

    Returns:
        The input DataFrame with `true_larger` and `true_diff_ratio`
        columns added (or overwritten).
    """
    assert isinstance(trials, pd.DataFrame)
    assert "test_a_size" in trials.columns
    assert "test_b_size" in trials.columns

    diff = trials["test_a_size"] - trials["test_b_size"]

    trials = trials.copy()
    trials["true_larger"] = np.where(
        np.abs(diff) <= tol, "equal",
        np.where(diff > 0, "a", "b")
    )

    max_size = np.maximum(trials["test_a_size"], trials["test_b_size"])
    trials["true_diff_ratio"] = np.abs(diff) / max_size

    # Equal trials should have exactly 0 diff_ratio
    trials.loc[trials["true_larger"] == "equal", "true_diff_ratio"] = 0.0

    return trials
