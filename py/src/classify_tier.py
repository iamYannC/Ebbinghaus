"""
classify_tier.py — Deterministic difficulty tier classifier

Pure function. No side effects.
Requires `true_larger` to be present (call verify_trial() first).

Tier definitions:
  0: Sanity check — no surrounds on either side
  1: Classic illusion — equal test sizes, different surround sizes
  2: Incongruent — test sizes differ, illusion opposes truth
  3: Congruent — test sizes differ, illusion reinforces truth
  NaN: Neutral / unclassifiable
"""

import math
import pandas as pd

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from config.defaults import FLOAT_TOLERANCE


def classify_tier(trials: pd.DataFrame, tol: float = FLOAT_TOLERANCE) -> pd.DataFrame:
    """Classify trials into difficulty tiers.

    Args:
        trials: DataFrame with trial parameters. Must include `true_larger`,
            `surround_a_n`, `surround_b_n`, `surround_a_size`, `surround_b_size`.
        tol: Floating-point tolerance for surround size equality.

    Returns:
        The input DataFrame with `tier` column added (or overwritten).
    """
    required = {"true_larger", "surround_a_n", "surround_b_n",
                "surround_a_size", "surround_b_size"}
    missing = required - set(trials.columns)
    if missing:
        raise ValueError(
            f"Missing required columns: {', '.join(missing)}. "
            "Did you run verify_trial() first?"
        )

    trials = trials.copy()
    tiers = [None] * len(trials)

    for i in range(len(trials)):
        sa_n = trials.iloc[i]["surround_a_n"]
        sb_n = trials.iloc[i]["surround_b_n"]
        sa_size = trials.iloc[i]["surround_a_size"]
        sb_size = trials.iloc[i]["surround_b_size"]
        truth = trials.iloc[i]["true_larger"]

        no_surround_a = pd.isna(sa_n) or sa_n == 0
        no_surround_b = pd.isna(sb_n) or sb_n == 0

        # Tier 0: No surrounds on either side
        if no_surround_a and no_surround_b:
            tiers[i] = 0
            continue

        # If only one side has surrounds, it's unclassifiable
        if no_surround_a or no_surround_b:
            tiers[i] = None
            continue

        # Both sides have surrounds
        surround_diff = sa_size - sb_size
        surrounds_equal = abs(surround_diff) <= tol

        if truth == "equal":
            tiers[i] = 1 if not surrounds_equal else None
            continue

        # Tests differ (truth is "a" or "b")
        if surrounds_equal:
            tiers[i] = None
            continue

        # Larger surrounds make the enclosed test look SMALLER.
        larger_has_bigger_surround = (
            (truth == "a" and sa_size > sb_size) or
            (truth == "b" and sb_size > sa_size)
        )

        tiers[i] = 2 if larger_has_bigger_surround else 3

    trials["tier"] = pd.array(tiers, dtype=pd.Int64Dtype())
    return trials
