# =============================================================================
# render_stimuli.R — Batch renderer
# =============================================================================
# Takes a trial data frame (or any subset) and renders each row to an image.
# Has no opinions about experimental design — renders whatever it receives.
# =============================================================================

source("Ebbinghaus/R/draw_trial.R")

#' Render stimulus images for a trial table
#'
#' @param trials A data frame with the trials table schema (or a subset).
#' @param verbose Logical: print progress messages. Default TRUE.
#'
#' @return Invisibly returns the input trials data frame. Side effect: writes
#'   image files to the paths specified in each row's `file_path` column.
render_stimuli <- function(trials, verbose = TRUE) {

  stopifnot(is.data.frame(trials), nrow(trials) > 0)

  # Ensure output directories exist
  dirs <- unique(dirname(trials$file_path))
  for (d in dirs) {
    if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  }

  n <- nrow(trials)
  errors <- character(0)

  for (i in seq_len(n)) {
    row <- trials[i, ]
    fpath <- row$file_path
    fmt <- row$file_format
    w <- row$canvas_width
    h <- row$canvas_height

    if (verbose && (i %% 10 == 0 || i == 1 || i == n)) {
      message(sprintf("[%d/%d] Rendering trial %d -> %s", i, n,
                      row$trial_id, fpath))
    }

    tryCatch({
      p <- draw_trial(row)

      if (fmt == "png") {
        ggsave(fpath, plot = p, width = w / 96, height = h / 96,
               dpi = 96, units = "in", bg = row$background_color)
      } else if (fmt == "svg") {
        ggsave(fpath, plot = p, width = w / 96, height = h / 96,
               units = "in", bg = row$background_color, device = "svg")
      } else if (fmt == "webp") {
        # webp via ragg if available, otherwise fall back to png
        if (requireNamespace("ragg", quietly = TRUE)) {
          ggsave(fpath, plot = p, width = w / 96, height = h / 96,
                 dpi = 96, units = "in", bg = row$background_color,
                 device = ragg::agg_png)
          # Rename .png to .webp — or use a proper webp device if available
          # For now, fall back to png with webp extension as placeholder
          warning("webp support is placeholder; saving as png with .webp extension")
        } else {
          warning("ragg not available; saving webp as png with .webp extension")
          ggsave(fpath, plot = p, width = w / 96, height = h / 96,
                 dpi = 96, units = "in", bg = row$background_color)
        }
      } else {
        stop("Unsupported file format: ", fmt)
      }

      if (!file.exists(fpath)) {
        errors <- c(errors, paste0("Trial ", row$trial_id, ": file not created"))
      }
    },
    error = function(e) {
      msg <- paste0("Trial ", row$trial_id, ": ", conditionMessage(e))
      errors <<- c(errors, msg)
      if (verbose) message("  ERROR: ", msg)
    })
  }

  if (length(errors) > 0) {
    warning(length(errors), " errors during rendering:\n",
            paste("  -", errors, collapse = "\n"))
  } else if (verbose) {
    message("All ", n, " stimuli rendered successfully.")
  }

  invisible(trials)
}
