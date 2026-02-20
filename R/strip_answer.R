# =============================================================================
# strip_answer.R — Strip ground-truth answer from image filenames
# =============================================================================
# Image files are saved as <id>_<true_larger>.<ext> for researcher convenience.
# Before sending images to AI models, use these functions to produce clean
# copies or paths that don't leak the answer.
# =============================================================================

#' Strip the answer and tier from a single file path
#'
#' Converts "images/42_equal_t1.png" -> "images/42.png"
#' Also handles the old format without tier: "images/42_equal.png" -> "images/42.png"
#'
#' @param path Character: file path in the format <id>_<answer>_t<tier>.<ext>
#' @return Character: cleaned path in the format <id>.<ext>
strip_answer_from_path <- function(path) {
  # Match: (anything/<digits>)_(equal|a|b)(_t[0-9NA]+)?.(ext)
  gsub("^(.+/\\d+)_(equal|a|b)(_t[0-9NA]+)?(\\.[a-z]+)$", "\\1\\4", path)
}


#' Create answer-stripped copies of image files for AI evaluation
#'
#' Copies each image to a clean filename (without the ground-truth answer)
#' in a target directory. Returns a modified trials data frame with updated
#' file_path pointing to the clean copies.
#'
#' @param trials Data frame with trials schema (needs `file_path` column).
#' @param output_dir Directory for the stripped copies. Default: "Ebbinghaus/images_eval"
#' @param verbose Print progress. Default TRUE.
#'
#' @return The input trials data frame with `file_path` updated to the
#'   stripped copies. Original `file_path` preserved in `file_path_original`.
strip_answer_from_images <- function(trials, output_dir = "images_eval",
                                     verbose = TRUE) {

  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  trials$file_path_original <- trials$file_path
  trials$file_path <- file.path(
    output_dir,
    basename(strip_answer_from_path(trials$file_path))
  )

  for (i in seq_len(nrow(trials))) {
    src <- trials$file_path_original[i]
    dst <- trials$file_path[i]

    # Normalize source path (remove leading "Ebbinghaus/" if present)
    src_normalized <- sub("^Ebbinghaus/", "", src)
    
    if (!file.exists(src_normalized)) {
      warning("Source file not found: ", src_normalized, " (original: ", src, ")")
      next
    }

    file.copy(src_normalized, dst, overwrite = TRUE)
  }

  if (verbose) {
    message("Copied ", nrow(trials), " images to ", output_dir,
            " with answer-stripped filenames.")
  }

  trials
}
