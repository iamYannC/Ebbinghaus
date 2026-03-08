"""
generate_design.py — Design matrix builder

Builds a complete trial table for an experiment. This is ONE provided
strategy. Researchers can also construct trial tables manually, by filtering,
or with custom generators.
"""

import os
import numpy as np
import pandas as pd

import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from config.defaults import DEFAULT_N_PER_TIER, DEFAULT_FILE_FORMAT
from src.generate_trial import generate_trial


def generate_design(
    seed: int | None = None,
    n_per_tier: int = DEFAULT_N_PER_TIER,
    file_format: str = DEFAULT_FILE_FORMAT,
    image_dir: str = "images",
    **kwargs,
) -> pd.DataFrame:
    """Generate a complete design matrix of trials.

    Creates a balanced trial table with representation across tiers.
    Each trial gets a unique trial_id and file_path.

    Args:
        seed: Master seed for the entire design.
        n_per_tier: Number of trials per tier (0, 1, 2, 3).
        file_format: Default file format for images.
        image_dir: Directory for images (relative to project root).
        **kwargs: Additional arguments passed to generate_trial().

    Returns:
        A DataFrame with complete trials schema, verified and classified.
    """
    rng = np.random.RandomState()

    if seed is None:
        seed = int(rng.randint(-1_000_000_000, 1_000_000_000))
        print(f"Using auto-generated master seed: {seed}")
    rng = np.random.RandomState(seed)

    total_trials = n_per_tier * 4
    trial_seeds = rng.randint(-1_000_000_000, 1_000_000_000, size=total_trials)

    # Stratified by tier
    tiers = []
    for t in range(4):
        tiers.extend([t] * n_per_tier)

    trials_list = []
    for i in range(total_trials):
        trial = generate_trial(
            seed=int(trial_seeds[i]),
            tier=tiers[i],
            file_format=file_format,
            **kwargs,
        )
        trials_list.append(trial)

    trials = pd.concat(trials_list, ignore_index=True)

    # Shuffle row order
    rng2 = np.random.RandomState(seed + 1)
    trials = trials.iloc[rng2.permutation(len(trials))].reset_index(drop=True)

    # Assign trial_id and file_path
    trials["trial_id"] = range(1, len(trials) + 1)
    tier_label = trials["tier"].apply(
        lambda t: "tNA" if pd.isna(t) else f"t{int(t)}"
    )
    trials["file_path"] = [
        os.path.join(
            image_dir,
            f"{tid}_{tl}_{tlab}.{fmt}"
        )
        for tid, tl, tlab, fmt in zip(
            trials["trial_id"],
            trials["true_larger"],
            tier_label,
            trials["file_format"],
        )
    ]

    return trials
