"""
generate_trial.py — Constrained random trial generator

Generates a single trial's parameters as a one-row DataFrame.
Optionally constrained by tier, orientation, shape, etc.
Every generated trial stores the seed used, for reproducibility.

Enforces:
  - Color/fill contrast against background (no invisible shapes)
  - No surround-to-test occlusion
  - No surround-to-surround overlap within a group
  - No cross-group overlap
"""

import math
import numpy as np
import pandas as pd

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from config.defaults import (
    SHAPE_POOL, TEST_SIZE_RANGE, SURROUND_SIZE_RANGE, SURROUND_N_RANGE,
    SURROUND_DISTANCE_RANGE, CANVAS_SIZES, COLOR_POOL, FILL_POOL,
    BACKGROUND_POOL, ORIENTATION_POOL, DEFAULT_FILE_FORMAT, FLOAT_TOLERANCE,
)
from src.verify_trial import verify_trial
from src.classify_tier import classify_tier


def pick_contrasting_color(rng, pool: list[str], bg: str) -> str:
    """Pick a color from a pool, ensuring contrast against background."""
    candidates = [c for c in pool if c is not None and c != bg]
    if not candidates:
        raise ValueError(f"No colors in pool contrast with background '{bg}'")
    return candidates[rng.randint(len(candidates))]


def pick_fill(rng, pool: list) -> str | None:
    """Pick a fill color (may be None for transparent)."""
    return pool[rng.randint(len(pool))]


def min_distance_no_surround_overlap(
    n: int, s: float, shape: str = "circle", gap_frac: float = 0.10
) -> float:
    """Minimum distance so adjacent surrounds in a ring don't overlap."""
    if n <= 1:
        return s
    effective_r = s * math.sqrt(2) if shape == "square" else s
    return effective_r * (1 + gap_frac) / math.sin(math.pi / n)


def group_separation(orientation: str, canvas_w: int, canvas_h: int) -> float:
    """Compute distance between group centers A and B."""
    if orientation == "horizontal":
        return canvas_w * 0.50
    elif orientation == "vertical":
        return canvas_h * 0.50
    elif orientation == "diagonal":
        return math.sqrt((canvas_w * 0.50) ** 2 + (canvas_h * 0.50) ** 2)
    else:
        raise ValueError(f"Unknown orientation: {orientation}")


def generate_trial(
    seed: int | None = None,
    tier: int | None = None,
    orientation: str | None = None,
    shape_pool: list[str] = SHAPE_POOL,
    size_range: tuple = TEST_SIZE_RANGE,
    surround_size_range: tuple = SURROUND_SIZE_RANGE,
    surround_n_range: tuple = SURROUND_N_RANGE,
    surround_distance_range: tuple = SURROUND_DISTANCE_RANGE,
    canvas_sizes: list[int] = CANVAS_SIZES,
    color_pool: list[str] = COLOR_POOL,
    fill_pool: list = FILL_POOL,
    background_pool: list[str] = BACKGROUND_POOL,
    orientation_pool: list[str] = ORIENTATION_POOL,
    file_format: str = DEFAULT_FILE_FORMAT,
) -> pd.DataFrame:
    """Generate a single random trial.

    Args:
        seed: Integer seed for reproducibility. None = generate a random seed.
        tier: Target tier (0, 1, 2, 3). None = unconstrained.
        orientation: Fixed orientation, or None for random.
        shape_pool: Shapes to sample from.
        size_range: (min, max) test size proportions.
        surround_size_range: (min, max) surround size proportions.
        surround_n_range: (min, max) surround count.
        surround_distance_range: (min, max) extra distance padding proportions.
        canvas_sizes: Candidate canvas dimensions.
        color_pool: Border colors.
        fill_pool: Fill colors (may include None).
        background_pool: Background colors.
        orientation_pool: Orientations to sample from.
        file_format: File format for rendering.

    Returns:
        A one-row DataFrame with the complete trials schema.
    """
    rng = np.random.RandomState()

    # --- Seed handling ---
    if seed is None:
        seed = int(rng.randint(0, 2_000_000_000))
    rng = np.random.RandomState(seed)

    # --- Orientation ---
    if orientation is None:
        orientation = orientation_pool[rng.randint(len(orientation_pool))]

    # --- Canvas ---
    canvas_w = canvas_sizes[rng.randint(len(canvas_sizes))]
    canvas_h = canvas_sizes[rng.randint(len(canvas_sizes))]
    bg_color = background_pool[rng.randint(len(background_pool))]

    # --- Scale factor ---
    scale = min(canvas_w, canvas_h)

    # --- Group separation ---
    group_sep = group_separation(orientation, canvas_w, canvas_h)

    # --- Test stimuli ---
    test_a_shape = shape_pool[rng.randint(len(shape_pool))]
    test_a_size = rng.uniform(size_range[0], size_range[1]) * scale
    test_a_color = pick_contrasting_color(rng, color_pool, bg_color)
    test_a_fill = pick_fill(rng, fill_pool)

    test_b_shape = shape_pool[rng.randint(len(shape_pool))]
    test_b_color = pick_contrasting_color(rng, color_pool, bg_color)
    test_b_fill = pick_fill(rng, fill_pool)

    # --- Surround base parameters ---
    surround_a_shape = shape_pool[rng.randint(len(shape_pool))]
    surround_a_color = pick_contrasting_color(rng, color_pool, bg_color)
    surround_a_fill = pick_fill(rng, fill_pool)
    surround_a_n = rng.randint(surround_n_range[0], surround_n_range[1] + 1)

    surround_b_shape = shape_pool[rng.randint(len(shape_pool))]
    surround_b_color = pick_contrasting_color(rng, color_pool, bg_color)
    surround_b_fill = pick_fill(rng, fill_pool)
    surround_b_n = rng.randint(surround_n_range[0], surround_n_range[1] + 1)

    # --- Cap surround size helper ---
    def cap_surround_size(raw_size, n, test_sz, test_shape, surr_shape, half_budget):
        eff_test = test_sz * math.sqrt(2) if test_shape == "square" else test_sz
        shape_factor = math.sqrt(2) if surr_shape == "square" else 1
        ring_factor = (1 + 0.30) / math.sin(math.pi / n) + 1 if n > 1 else 2.3
        max_s = (half_budget - eff_test) / (shape_factor * ring_factor)
        max_s = max(max_s, surround_size_range[0] * scale)
        return min(raw_size, max_s)

    half_budget = group_sep * (1 - 0.30) / 2

    # --- Tier-constrained logic ---
    if tier is not None and pd.isna(tier):
        raise ValueError(
            "tier = NaN is not a valid target. Use None for unconstrained."
        )

    if tier is None:
        test_b_size = rng.uniform(size_range[0], size_range[1]) * scale
        surround_a_size = rng.uniform(surround_size_range[0], surround_size_range[1]) * scale
        surround_b_size = rng.uniform(surround_size_range[0], surround_size_range[1]) * scale
        if surround_a_n > 0:
            surround_a_size = cap_surround_size(surround_a_size, surround_a_n, test_a_size, test_a_shape, surround_a_shape, half_budget)
        if surround_b_n > 0:
            surround_b_size = cap_surround_size(surround_b_size, surround_b_n, test_b_size, test_b_shape, surround_b_shape, half_budget)

    elif tier == 0:
        test_b_size = rng.uniform(size_range[0], size_range[1]) * scale
        surround_a_n = 0
        surround_b_n = 0
        surround_a_shape = None
        surround_a_size = float("nan")
        surround_a_color = None
        surround_a_fill = None
        surround_b_shape = None
        surround_b_size = float("nan")
        surround_b_color = None
        surround_b_fill = None

    elif tier == 1:
        test_b_size = test_a_size
        surround_a_size = rng.uniform(surround_size_range[0], surround_size_range[1]) * scale
        surround_a_size = cap_surround_size(surround_a_size, surround_a_n, test_a_size, test_a_shape, surround_a_shape, half_budget)
        while True:
            surround_b_size = rng.uniform(surround_size_range[0], surround_size_range[1]) * scale
            surround_b_size = cap_surround_size(surround_b_size, surround_b_n, test_b_size, test_b_shape, surround_b_shape, half_budget)
            if abs(surround_a_size - surround_b_size) > FLOAT_TOLERANCE:
                break

    elif tier in (2, 3):
        while True:
            test_b_size = rng.uniform(size_range[0], size_range[1]) * scale
            if abs(test_a_size - test_b_size) > FLOAT_TOLERANCE:
                break
        a_is_larger = test_a_size > test_b_size

        mid_surr = (surround_size_range[0] + surround_size_range[1]) / 2
        big_surr = rng.uniform(mid_surr, surround_size_range[1]) * scale
        small_surr = rng.uniform(surround_size_range[0], mid_surr) * scale

        if (tier == 2 and a_is_larger) or (tier == 3 and not a_is_larger):
            raw_a, raw_b = big_surr, small_surr
        else:
            raw_a, raw_b = small_surr, big_surr

        surround_a_size = cap_surround_size(raw_a, surround_a_n, test_a_size, test_a_shape, surround_a_shape, half_budget)
        surround_b_size = cap_surround_size(raw_b, surround_b_n, test_b_size, test_b_shape, surround_b_shape, half_budget)

        if raw_a > raw_b and surround_a_size <= surround_b_size:
            surround_b_size = surround_a_size * 0.7
        elif raw_b > raw_a and surround_b_size <= surround_a_size:
            surround_a_size = surround_b_size * 0.7
    else:
        raise ValueError(f"Invalid tier: {tier}. Must be 0, 1, 2, 3, or None.")

    # --- Surround distances ---
    gap_frac = 0.30
    eff_test_a = test_a_size * math.sqrt(2) if test_a_shape == "square" else test_a_size
    eff_test_b = test_b_size * math.sqrt(2) if test_b_shape == "square" else test_b_size

    min_dist_a = 0.0
    min_dist_b = 0.0
    eff_surr_a = 0.0
    eff_surr_b = 0.0

    if surround_a_n > 0:
        eff_surr_a = surround_a_size * math.sqrt(2) if surround_a_shape == "square" else surround_a_size
        min_dist_test_a = eff_test_a + eff_surr_a * (1 + gap_frac)
        min_dist_ring_a = min_distance_no_surround_overlap(
            surround_a_n, surround_a_size, surround_a_shape, gap_frac
        )
        min_dist_a = max(min_dist_test_a, min_dist_ring_a)

    if surround_b_n > 0:
        eff_surr_b = surround_b_size * math.sqrt(2) if surround_b_shape == "square" else surround_b_size
        min_dist_test_b = eff_test_b + eff_surr_b * (1 + gap_frac)
        min_dist_ring_b = min_distance_no_surround_overlap(
            surround_b_n, surround_b_size, surround_b_shape, gap_frac
        )
        min_dist_b = max(min_dist_test_b, min_dist_ring_b)

    cross_budget = group_sep * (1 - gap_frac) - eff_surr_a - eff_surr_b
    total_min = min_dist_a + min_dist_b

    if surround_a_n > 0 and surround_b_n > 0:
        if cross_budget < total_min:
            max_dist_a = min_dist_a
            max_dist_b = min_dist_b
        else:
            remaining = cross_budget - total_min
            padding = remaining * 0.3
            max_dist_a = min_dist_a + padding * (min_dist_a / total_min) if total_min > 0 else min_dist_a
            max_dist_b = min_dist_b + padding * (min_dist_b / total_min) if total_min > 0 else min_dist_b
        surround_a_distance = rng.uniform(min_dist_a, max(min_dist_a, max_dist_a))
        surround_b_distance = rng.uniform(min_dist_b, max(min_dist_b, max_dist_b))

    elif surround_a_n > 0:
        max_dist_a = group_sep * (1 - gap_frac) - eff_surr_a - eff_test_b
        padding_a = surround_distance_range[1] * scale * 0.3
        max_dist_a = min(max_dist_a, min_dist_a + padding_a)
        if max_dist_a < min_dist_a:
            max_dist_a = min_dist_a
        surround_a_distance = rng.uniform(min_dist_a, max_dist_a)
        surround_b_distance = float("nan")

    elif surround_b_n > 0:
        max_dist_b = group_sep * (1 - gap_frac) - eff_surr_b - eff_test_a
        padding_b = surround_distance_range[1] * scale * 0.3
        max_dist_b = min(max_dist_b, min_dist_b + padding_b)
        if max_dist_b < min_dist_b:
            max_dist_b = min_dist_b
        surround_b_distance = rng.uniform(min_dist_b, max_dist_b)
        surround_a_distance = float("nan")

    else:
        surround_a_distance = float("nan")
        surround_b_distance = float("nan")

    # --- Assemble the row ---
    trial = pd.DataFrame([{
        "trial_id": None,
        "n_comparisons": 2,
        "orientation": orientation,
        "canvas_width": canvas_w,
        "canvas_height": canvas_h,
        "background_color": bg_color,
        "test_a_shape": test_a_shape,
        "test_a_size": test_a_size,
        "test_a_color": test_a_color,
        "test_a_fill": test_a_fill,
        "test_b_shape": test_b_shape,
        "test_b_size": test_b_size,
        "test_b_color": test_b_color,
        "test_b_fill": test_b_fill,
        "surround_a_shape": surround_a_shape,
        "surround_a_size": surround_a_size,
        "surround_a_n": surround_a_n,
        "surround_a_color": surround_a_color,
        "surround_a_fill": surround_a_fill,
        "surround_a_distance": surround_a_distance,
        "surround_b_shape": surround_b_shape,
        "surround_b_size": surround_b_size,
        "surround_b_n": surround_b_n,
        "surround_b_color": surround_b_color,
        "surround_b_fill": surround_b_fill,
        "surround_b_distance": surround_b_distance,
        "seed": seed,
        "file_format": file_format,
        "file_path": None,
        "created_with": "py",
    }])

    # --- Verify and classify ---
    trial = verify_trial(trial)
    trial = classify_tier(trial)

    # --- Sanity check ---
    if tier is not None:
        actual_tier = trial["tier"].iloc[0]
        if pd.isna(actual_tier) or actual_tier != tier:
            raise RuntimeError(
                f"Generated trial classified as tier {actual_tier} "
                f"but tier {tier} was requested. This is a bug."
            )

    return trial
