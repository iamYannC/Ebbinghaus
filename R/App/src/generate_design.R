# =============================================================================
# generate_design.R — Design matrix builder
# =============================================================================
# Builds a complete trial table for an experiment. This is ONE provided
# strategy. Researchers can also construct trial tables manually, by filtering,
# or with custom generators. All downstream functions accept any data frame
# with the correct schema.
# =============================================================================

# source("R/generate_trial.R")  # handled by app.R

#' Generate a complete design matrix of trials
#'
#' Creates a balanced trial table with representation across tiers.
#' Each trial gets a unique trial_id and file_path.
#'
#' @param seed Master seed for the entire design. Individual trial seeds are
#'   derived deterministically from this.
#' @param n_per_tier Integer: number of trials per tier (0, 1, 2, 3).
#' @param file_format Default file format for images.
#' @param image_dir Directory for images (relative to project root).
#' @param ... Additional arguments passed to generate_trial() (e.g.,
#'   shape_pool, size_range, color_pool, etc.)
#'
#' @return A data frame with complete trials schema, verified and classified.
#'   Not written to disk automatically—use
#'   `write.csv(trials, "data/trials.csv", row.names = FALSE)` to persist.
generate_design <- function(
    seed        = NULL,
    n_per_tier  = DEFAULT_N_PER_TIER,
    file_format = DEFAULT_FILE_FORMAT,
    image_dir   = "images",
    ...
) {

  # --- Master seed ---
  if (is.null(seed)) {
    seed <- round(runif(1, -1e9, 1e9))
    message("Using auto-generated master seed: ", seed)
  }
  set.seed(seed)

  # --- Generate per-trial seeds deterministically from master seed ---
  total_trials <- n_per_tier * 4L
  trial_seeds <- round(runif(total_trials, -1e9, 1e9))

  # --- Generate trials, stratified by tier ---
  tiers <- rep(0:3, each = n_per_tier)
  trials_list <- vector("list", total_trials)

  for (i in seq_len(total_trials)) {
    trials_list[[i]] <- generate_trial(
      seed = trial_seeds[i],
      tier = tiers[i],
      file_format = file_format,
      ...
    )
  }

  trials <- do.call(rbind, trials_list)

  # --- Shuffle row order (so tiers are interleaved, not blocked) ---
  set.seed(seed + 1L)
  trials <- trials[sample(nrow(trials)), ]

  # --- Assign trial_id and file_path ---
  # Naming convention: <trial_id>_<true_larger>_t<tier>.<ext>
  # e.g., "1_equal_t1.png", "2_a_t2.png", "3_b_t0.png"
  # This encodes ground truth and tier in the filename for researcher convenience.
  # IMPORTANT: Before sending images to AI models for evaluation, use
  # strip_answer_from_path() to produce a clean copy without the answer/tier.
  trials$trial_id <- seq_len(nrow(trials))
  trials$master_seed <- seed
  tier_label <- ifelse(is.na(trials$tier), "tNA", paste0("t", trials$tier))
  trials$file_path <- file.path(
    image_dir,
    paste0(trials$trial_id, "_", trials$true_larger, "_", tier_label, ".", trials$file_format)
  )
  rownames(trials) <- NULL

  trials
}
