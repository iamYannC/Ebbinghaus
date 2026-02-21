# =============================================================================
# generate_trial.R — Constrained random trial generator
# =============================================================================
# Generates a single trial's parameters as a one-row data frame.
# Optionally constrained by tier, orientation, shape, etc.
# Every generated trial stores the seed used, for reproducibility.
#
# Enforces:
#   - Color/fill contrast against background (no invisible shapes)
#   - No surround-to-test occlusion (surrounds don't cover test shape)
#   - No surround-to-surround overlap within a group
#   - No cross-group overlap (group A surrounds don't reach group B test)
# =============================================================================

source("config/defaults.R")
source("R/verify_trial.R")
source("R/classify_tier.R")


# =============================================================================
# Validation helpers
# =============================================================================

#' Pick a color from a pool, ensuring contrast against background
#'
#' @param pool Color pool to sample from
#' @param bg Background color to contrast against
#' @return A color different from bg
pick_contrasting_color <- function(pool, bg) {
  # Remove bg and NA from candidates for border color
  candidates <- setdiff(pool[!is.na(pool)], bg)
  if (length(candidates) == 0) {
    stop("No colors in pool contrast with background '", bg, "'")
  }
  sample(candidates, 1)
}

#' Pick a fill color, ensuring at least the border will be visible
#' Fill CAN be NA (no fill), and CAN match bg if the border contrasts.
#'
#' @param pool Fill pool (may include NA)
#' @return A fill color (possibly NA)
pick_fill <- function(pool) {
  sample(pool, 1)
}

#' Minimum distance so adjacent surrounds in a ring don't overlap.
#'
#' N shapes equally spaced on a circle of radius `d`.
#' Adjacent centers are 2*d*sin(pi/n) apart. They don't overlap when
#' that spacing >= 2*effective_radius. So: d >= effective_radius / sin(pi/n).
#'
#' For circles, effective_radius = s (the radius).
#' For squares, effective_radius = s * sqrt(2) (half-diagonal, worst case
#' since squares are axis-aligned and rotated positions on the ring mean
#' corners can point at neighbors).
#'
#' @param n Number of surrounds
#' @param s Surround size (radius or half-side)
#' @param shape Shape type ("circle" or "square")
#' @param gap_frac Fractional gap between adjacent surrounds (e.g., 0.1 = 10%)
#' @return Minimum distance (center of test to center of surround)
min_distance_no_surround_overlap <- function(n, s, shape = "circle", gap_frac = 0.10) {
  if (n <= 1) return(s)
  # Effective radius: worst-case extent from center
  effective_r <- if (shape == "square") s * sqrt(2) else s
  effective_r * (1 + gap_frac) / sin(pi / n)
}

#' Maximum extent of a surround group from the test center.
#' This is the surround distance + effective surround radius (the outer edge).
#'
#' @param distance Center-to-center distance
#' @param surround_size Surround radius/half-side
#' @param shape Shape type ("circle" or "square")
#' @return Outer extent radius
surround_outer_extent <- function(distance, surround_size, shape = "circle") {
  effective_r <- if (shape == "square") surround_size * sqrt(2) else surround_size
  distance + effective_r
}

#' Compute the distance between group centers A and B.
#'
#' @param orientation Trial orientation
#' @param canvas_w Canvas width
#' @param canvas_h Canvas height
#' @return Distance in plot units between group A center and group B center
group_separation <- function(orientation, canvas_w, canvas_h) {
  switch(orientation,
    horizontal = canvas_w * 0.50,     # 0.75w - 0.25w
    vertical   = canvas_h * 0.50,     # 0.75h - 0.25h
    diagonal   = sqrt((canvas_w * 0.50)^2 + (canvas_h * 0.50)^2),
    stop("Unknown orientation: ", orientation)
  )
}


# =============================================================================
# Main generator
# =============================================================================

#' Generate a single random trial
#'
#' @param seed Integer seed for reproducibility. `NULL` = generate a random seed.
#' @param tier Target tier (`0`, `1`, `2`, `3`). `NULL` = unconstrained (any tier
#'   may result). `NA` is not valid—`NA` tiers are only produced by
#'   [classify_tier()] for neutral/unclassifiable trials.
#' @param orientation Fixed orientation, or NULL for random.
#' @param shape_pool Character vector of shapes to sample from.
#' @param size_range Numeric vector of length 2: min and max test size (proportions).
#' @param surround_size_range Numeric vector of length 2: min and max surround size (proportions).
#' @param surround_n_range Integer vector of length 2: min and max surround count.
#' @param surround_distance_range Numeric vector of length 2: extra distance padding (proportions).
#' @param canvas_sizes Integer vector of candidate canvas dimensions.
#' @param color_pool Character vector of border colors.
#' @param fill_pool Character vector of fill colors (may include NA).
#' @param background_pool Character vector of background colors.
#' @param orientation_pool Character vector of orientations to sample from.
#' @param file_format File format for rendering.
#'
#' @note Default values are set in config/defaults.R
#' @return A one-row data frame with the complete trials schema.
generate_trial <- function(
    seed                    = NULL,
    tier                    = NULL,
    orientation             = NULL,
    shape_pool              = SHAPE_POOL,
    size_range              = TEST_SIZE_RANGE,
    surround_size_range     = SURROUND_SIZE_RANGE,
    surround_n_range        = SURROUND_N_RANGE,
    surround_distance_range = SURROUND_DISTANCE_RANGE,
    canvas_sizes            = CANVAS_SIZES,
    color_pool              = COLOR_POOL,
    fill_pool               = FILL_POOL,
    background_pool         = BACKGROUND_POOL,
    orientation_pool        = ORIENTATION_POOL,
    file_format             = DEFAULT_FILE_FORMAT
) {

  # --- Seed handling ---
  if (is.null(seed)) {
    seed <- round(runif(1, -1e9, 1e9))
  }
  set.seed(seed)

  # --- Orientation ---
  if (is.null(orientation)) {
    orientation <- sample(orientation_pool, 1)
  }

  # --- Canvas ---
  canvas_w <- sample(canvas_sizes, 1)
  canvas_h <- sample(canvas_sizes, 1)
  bg_color <- sample(background_pool, 1)

  # --- Scale factor: convert proportions to plot units ---
  scale <- min(canvas_w, canvas_h)

  # --- Compute group separation (how far apart groups A and B are) ---
  group_sep <- group_separation(orientation, canvas_w, canvas_h)

  # --- Test stimuli base parameters ---
  # Note: test_b_size is NOT set here. It is assigned in the tier-constrained

  # logic below, because it depends on the target tier (e.g., equal to
  # test_a_size for Tier 1, forced to differ for Tiers 2/3).
  test_a_shape <- sample(shape_pool, 1)
  test_a_size  <- runif(1, size_range[1], size_range[2]) * scale
  test_a_color <- pick_contrasting_color(color_pool, bg_color)
  test_a_fill  <- pick_fill(fill_pool)

  test_b_shape <- sample(shape_pool, 1)
  test_b_color <- pick_contrasting_color(color_pool, bg_color)
  test_b_fill  <- pick_fill(fill_pool)

  # --- Surround base parameters (shape, color — not yet sizes) ---
  surround_a_shape <- sample(shape_pool, 1)
  surround_a_color <- pick_contrasting_color(color_pool, bg_color)
  surround_a_fill  <- pick_fill(fill_pool)
  surround_a_n     <- sample(surround_n_range[1]:surround_n_range[2], 1)

  surround_b_shape <- sample(shape_pool, 1)
  surround_b_color <- pick_contrasting_color(color_pool, bg_color)
  surround_b_fill  <- pick_fill(fill_pool)
  surround_b_n     <- sample(surround_n_range[1]:surround_n_range[2], 1)

  # --- Helper: cap surround size so it fits within the available space ---
  # Given n surrounds, test_size, other_test_size, group_sep, and shape,
  # compute the maximum surround size that allows:
  #   1. Surrounds don't overlap each other in the ring
  #   2. The group's outer extent doesn't exceed half the group separation
  # We use half group_sep as the budget per side (conservative).
  # If you really feel like, you are welcome to modify this, just remember: you break you pay...
  cap_surround_size <- function(raw_size, n, test_sz, test_shape, surr_shape, half_budget) {
    eff_test <- if (test_shape == "square") test_sz * sqrt(2) else test_sz
    shape_factor <- if (surr_shape == "square") sqrt(2) else 1
    # From ring constraint: d >= s * shape_factor * (1+gap) / sin(pi/n)
    # outer_extent = d + s * shape_factor
    # So outer_extent >= s * shape_factor * ((1+gap)/sin(pi/n) + 1)
    # We need outer_extent + eff_test < half_budget
    # So s < (half_budget - eff_test) / (shape_factor * ((1+gap)/sin(pi/n) + 1))
    ring_factor <- if (n > 1) (1 + 0.30) / sin(pi / n) + 1 else 2.3
    max_s <- (half_budget - eff_test) / (shape_factor * ring_factor)
    max_s <- max(max_s, surround_size_range[1] * scale)  # never go below min
    min(raw_size, max_s)
  }

  half_budget <- group_sep * (1 - 0.30) / 2  # each group gets half, with gap

  # --- Tier-constrained logic for SIZES ---
  # NULL = unconstrained (generate freely, any tier may result).

  # NA is not a valid request: NA_integer_ is an *output* of classify_tier()

  # for neutral/unclassifiable trials, not something that can be targeted.
  if (!is.null(tier) && is.na(tier)) {
    stop("tier = NA is not a valid target. Use NULL for unconstrained generation. ",
         "NA tiers are only assigned by classify_tier() for neutral/unclassifiable trials.")
  }

  if (is.null(tier)) {
    test_b_size      <- runif(1, size_range[1], size_range[2]) * scale
    surround_a_size  <- runif(1, surround_size_range[1], surround_size_range[2]) * scale
    surround_b_size  <- runif(1, surround_size_range[1], surround_size_range[2]) * scale
    if (surround_a_n > 0)
      surround_a_size <- cap_surround_size(surround_a_size, surround_a_n, test_a_size, test_a_shape, surround_a_shape, half_budget)
    if (surround_b_n > 0)
      surround_b_size <- cap_surround_size(surround_b_size, surround_b_n, test_b_size, test_b_shape, surround_b_shape, half_budget)

  } else if (tier == 0L) {
    test_b_size      <- runif(1, size_range[1], size_range[2]) * scale
    surround_a_n     <- 0L
    surround_b_n     <- 0L
    surround_a_shape <- NA_character_
    surround_a_size  <- NA_real_
    surround_a_color <- NA_character_
    surround_a_fill  <- NA_character_
    surround_b_shape <- NA_character_
    surround_b_size  <- NA_real_
    surround_b_color <- NA_character_
    surround_b_fill  <- NA_character_

  } else if (tier == 1L) {
    test_b_size     <- test_a_size
    surround_a_size <- runif(1, surround_size_range[1], surround_size_range[2]) * scale
    surround_a_size <- cap_surround_size(surround_a_size, surround_a_n, test_a_size, test_a_shape, surround_a_shape, half_budget)
    repeat {
      surround_b_size <- runif(1, surround_size_range[1], surround_size_range[2]) * scale
      surround_b_size <- cap_surround_size(surround_b_size, surround_b_n, test_b_size, test_b_shape, surround_b_shape, half_budget)
      if (abs(surround_a_size - surround_b_size) > FLOAT_TOLERANCE) break
    }

  } else if (tier == 2L || tier == 3L) {
    repeat {
      test_b_size <- runif(1, size_range[1], size_range[2]) * scale
      if (abs(test_a_size - test_b_size) > FLOAT_TOLERANCE) break
    }
    a_is_larger <- test_a_size > test_b_size

    # For tier 2 (incongruent): larger test gets bigger surround
    # For tier 3 (congruent):   larger test gets smaller surround
    big_surr  <- runif(1, mean(surround_size_range), surround_size_range[2]) * scale
    small_surr <- runif(1, surround_size_range[1], mean(surround_size_range)) * scale

    # Determine which side gets big vs small
    if ((tier == 2L && a_is_larger) || (tier == 3L && !a_is_larger)) {
      # A gets big surround
      raw_a <- big_surr
      raw_b <- small_surr
    } else {
      # B gets big surround
      raw_a <- small_surr
      raw_b <- big_surr
    }

    # Cap both, then ensure the intended relationship still holds
    surround_a_size <- cap_surround_size(raw_a, surround_a_n, test_a_size, test_a_shape, surround_a_shape, half_budget)
    surround_b_size <- cap_surround_size(raw_b, surround_b_n, test_b_size, test_b_shape, surround_b_shape, half_budget)

    # If capping broke the big/small relationship, adjust the "small" one down
    if (raw_a > raw_b && surround_a_size <= surround_b_size) {
      surround_b_size <- surround_a_size * 0.7
    } else if (raw_b > raw_a && surround_b_size <= surround_a_size) {
      surround_a_size <- surround_b_size * 0.7
    }

  } else {
    stop("Invalid tier: ", tier, ". Must be 0, 1, 2, 3, or NULL (unconstrained).")
  }

  # =========================================================================
  # Surround distances — enforce ALL geometric constraints
  # =========================================================================
  gap_frac <- 0.30  # 30% gap between adjacent shapes (ensures visible separation)

  # Effective radii: for squares, the worst-case extent is the half-diagonal
  eff_test_a <- if (test_a_shape == "square") test_a_size * sqrt(2) else test_a_size
  eff_test_b <- if (test_b_shape == "square") test_b_size * sqrt(2) else test_b_size

  # Compute min distances for each group independently first (constraints 1 & 2)
  min_dist_a <- 0
  min_dist_b <- 0
  eff_surr_a <- 0
  eff_surr_b <- 0

  if (surround_a_n > 0) {
    eff_surr_a <- if (surround_a_shape == "square") surround_a_size * sqrt(2) else surround_a_size
    # Constraint 1: surrounds don't cover the test shape
    min_dist_test_a <- eff_test_a + eff_surr_a * (1 + gap_frac)
    # Constraint 2: adjacent surrounds in the ring don't overlap each other
    min_dist_ring_a <- min_distance_no_surround_overlap(
      surround_a_n, surround_a_size, surround_a_shape, gap_frac
    )
    min_dist_a <- max(min_dist_test_a, min_dist_ring_a)
  }

  if (surround_b_n > 0) {
    eff_surr_b <- if (surround_b_shape == "square") surround_b_size * sqrt(2) else surround_b_size
    min_dist_test_b <- eff_test_b + eff_surr_b * (1 + gap_frac)
    min_dist_ring_b <- min_distance_no_surround_overlap(
      surround_b_n, surround_b_size, surround_b_shape, gap_frac
    )
    min_dist_b <- max(min_dist_test_b, min_dist_ring_b)
  }

  # Constraint 3: cross-group separation
  # outer_extent_a = distance_a + eff_surr_a
  # outer_extent_b = distance_b + eff_surr_b
  # We need: outer_extent_a + outer_extent_b < group_sep (with gap)
  # i.e.: distance_a + eff_surr_a + distance_b + eff_surr_b < group_sep * (1 - gap_frac)
  # So the total budget for (distance_a + distance_b) is:
  cross_budget <- group_sep * (1 - gap_frac) - eff_surr_a - eff_surr_b
  total_min <- min_dist_a + min_dist_b

  # If both groups have surrounds, split the budget proportionally
  if (surround_a_n > 0 && surround_b_n > 0) {
    # Each group gets at least its minimum, then share remaining budget
    if (cross_budget < total_min) {
      # Constraints are contradictory — use minimums (tight fit)
      max_dist_a <- min_dist_a
      max_dist_b <- min_dist_b
    } else {
      remaining <- cross_budget - total_min
      padding <- remaining * 0.3  # use up to 30% of slack as random padding
      max_dist_a <- min_dist_a + padding * (min_dist_a / total_min)
      max_dist_b <- min_dist_b + padding * (min_dist_b / total_min)
    }
    surround_a_distance <- runif(1, min_dist_a, max_dist_a)
    surround_b_distance <- runif(1, min_dist_b, max_dist_b)

  } else if (surround_a_n > 0) {
    max_dist_a <- group_sep * (1 - gap_frac) - eff_surr_a - eff_test_b
    padding_a <- surround_distance_range[2] * scale * 0.3
    max_dist_a <- min(max_dist_a, min_dist_a + padding_a)
    if (max_dist_a < min_dist_a) max_dist_a <- min_dist_a
    surround_a_distance <- runif(1, min_dist_a, max_dist_a)
    surround_b_distance <- NA_real_

  } else if (surround_b_n > 0) {
    max_dist_b <- group_sep * (1 - gap_frac) - eff_surr_b - eff_test_a
    padding_b <- surround_distance_range[2] * scale * 0.3
    max_dist_b <- min(max_dist_b, min_dist_b + padding_b)
    if (max_dist_b < min_dist_b) max_dist_b <- min_dist_b
    surround_b_distance <- runif(1, min_dist_b, max_dist_b)
    surround_a_distance <- NA_real_

  } else {
    surround_a_distance <- NA_real_
    surround_b_distance <- NA_real_
  }

  # --- Assemble the row ---
  trial <- data.frame(
    trial_id            = NA_integer_,
    n_comparisons       = 2L,
    orientation         = orientation,
    canvas_width        = canvas_w,
    canvas_height       = canvas_h,
    background_color    = bg_color,
    test_a_shape        = test_a_shape,
    test_a_size         = test_a_size,
    test_a_color        = test_a_color,
    test_a_fill         = test_a_fill,
    test_b_shape        = test_b_shape,
    test_b_size         = test_b_size,
    test_b_color        = test_b_color,
    test_b_fill         = test_b_fill,
    surround_a_shape    = surround_a_shape,
    surround_a_size     = surround_a_size,
    surround_a_n        = surround_a_n,
    surround_a_color    = surround_a_color,
    surround_a_fill     = surround_a_fill,
    surround_a_distance = surround_a_distance,
    surround_b_shape    = surround_b_shape,
    surround_b_size     = surround_b_size,
    surround_b_n        = surround_b_n,
    surround_b_color    = surround_b_color,
    surround_b_fill     = surround_b_fill,
    surround_b_distance = surround_b_distance,
    seed                = seed,
    file_format         = file_format,
    file_path           = NA_character_,
    stringsAsFactors    = FALSE
  )

  # --- Verify and classify ---
  trial <- verify_trial(trial)
  trial <- classify_tier(trial)

  # --- Sanity check: if tier was requested, confirm it matches ---
  if (!is.null(tier)) {
    actual_tier <- trial$tier
    if (is.na(actual_tier) || actual_tier != tier) {
      stop("Generated trial classified as tier ", actual_tier,
           " but tier ", tier, " was requested. This is a bug.")
    }
  }

  trial
}
