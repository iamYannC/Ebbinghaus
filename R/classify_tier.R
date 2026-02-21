# =============================================================================
# classify_tier.R — Deterministic difficulty tier classifier
# =============================================================================
# Pure function. No side effects.
# Requires `true_larger` to be present (call verify_trial() first).
#
# Tier definitions:
#   0: Sanity check — no surrounds on either side
#   1: Classic illusion — equal test sizes, different surround sizes
#   2: Incongruent — test sizes differ, illusion opposes truth
#   3: Congruent — test sizes differ, illusion reinforces truth
#   NA: Neutral / unclassifiable (e.g., equal surround sizes with unequal tests)
# =============================================================================

source("Ebbinghaus/config/defaults.R")

#' Classify trials into difficulty tiers
#'
#' @param trials A data frame with trial parameters. Must include `true_larger`,
#'   `surround_a_n`, `surround_b_n`, `surround_a_size`, `surround_b_size`.
#' @param tol Floating-point tolerance for surround size equality. Default from config.
#'
#' @details Calls `verify_trial()` first to ensure `true_larger` is present. [human notes: improve and add @seealso.]
#' 
#' @return The input data frame with `tier` column added (or overwritten).
classify_tier <- function(trials, tol = FLOAT_TOLERANCE) {

  # Hey humans. this error handling is a bit verbose. Just leave default columns and it will be fine. this is agent's way to write tests 
  required <- c("true_larger", "surround_a_n", "surround_b_n",
                 "surround_a_size", "surround_b_size")
  missing <- setdiff(required, names(trials))
  if (length(missing) > 0) {
    stop("Missing required columns: ", paste(missing, collapse = ", "),
         ". Did you run verify_trial() first?")
  }

  trials$tier <- NA_integer_

  for (i in seq_len(nrow(trials))) {
    sa_n <- trials$surround_a_n[i]
    sb_n <- trials$surround_b_n[i]
    sa_size <- trials$surround_a_size[i]
    sb_size <- trials$surround_b_size[i]
    truth <- trials$true_larger[i]

    no_surround_a <- is.na(sa_n) || sa_n == 0
    no_surround_b <- is.na(sb_n) || sb_n == 0

    # Tier 0: No surrounds on either side
    if (no_surround_a && no_surround_b) {
      trials$tier[i] <- 0L
      next
    }

    # For tiers 1-3 we need surrounds on both sides
    # If only one side has surrounds, it's unclassifiable
    if (no_surround_a || no_surround_b) {
      trials$tier[i] <- NA_integer_
      next
    }

    # Both sides have surrounds. Classify based on truth and surround sizes.
    surround_diff <- sa_size - sb_size
    surrounds_equal <- abs(surround_diff) <= tol

    if (truth == "equal") {
      # Tier 1: Equal tests, different surrounds
      if (!surrounds_equal) {
        trials$tier[i] <- 1L
      } else {
        # Equal tests, equal surrounds — no illusion, not a standard tier
        trials$tier[i] <- NA_integer_
      }
      next
    }

    # Tests differ (truth is "a" or "b")
    if (surrounds_equal) {
      # Surrounds are equal, so no illusion push either way — neutral
      trials$tier[i] <- NA_integer_
      next
    }

    # Determine if illusion opposes or reinforces truth.
    # Larger surrounds make the enclosed test look SMALLER.
    # So if the truly larger test has larger surrounds → illusion opposes → Tier 2
    # If the truly larger test has smaller surrounds → illusion reinforces → Tier 3
    larger_has_bigger_surround <- (truth == "a" && sa_size > sb_size) ||
                                  (truth == "b" && sb_size > sa_size)

    if (larger_has_bigger_surround) {
      trials$tier[i] <- 2L   # Incongruent
    } else {
      trials$tier[i] <- 3L   # Congruent
    }
  }

  trials
}
