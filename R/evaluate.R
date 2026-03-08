# =============================================================================
# evaluate.R — Phase 2: Evaluation Pipeline (vitals-based)
# =============================================================================
# Evaluates VLM performance on the Ebbinghaus benchmark using the `vitals`
# framework for structured logging, parallel evaluation, and analysis.
#
# Provides:
#   build_dataset()        — construct a vitals-compatible dataset tibble
#   ebbinghaus_solver()    — custom solver: sends image + text to VLM
#   ebbinghaus_scorer()    — custom scorer: deterministic parse + compare
#   run_evals()            — high-level orchestration across prompts × models
#   fill_prompt()          — resolve prompt template placeholders
#   parse_response()       — extract canonical answer from raw model text
#
# Uses `vitals` for task orchestration and `ellmer` for LLM interaction.
# API keys are read from environment variables by ellmer:
#   ANTHROPIC_API_KEY, OPENAI_API_KEY, GOOGLE_API_KEY
#
# Usage:
#   source("R/evaluate.R")
#
#   trials  <- read.csv("data/trials.csv", stringsAsFactors = FALSE)
#   prompts <- read.csv("data/prompts.csv", stringsAsFactors = FALSE)
#
#   tasks <- run_evals(
#     trials  = trials,
#     prompts = prompts,
#     models  = list(
#       list(provider = "openai",    model = "gpt-5.4-pro"),
#       list(provider = "anthropic", model = "claude-sonnet-4-6")
#     )
#   )
# =============================================================================

library(vitals)
library(ellmer)
library(tibble)
library(purrr)

source("R/strip_answer.R")

# =============================================================================
# Direction helpers
# =============================================================================

DIRECTION_WORDS <- list(
  horizontal = list(a = "left",       b = "right"),
  vertical   = list(a = "top",        b = "bottom"),
  diagonal   = list(a = "upper-left", b = "lower-right")
)

#' Fill prompt template placeholders for a specific trial row.
#'
#' Replaces `{direction_a}`, `{direction_b}`, `{test_a_shape}`, etc. with
#' values from the trial. Unknown placeholders are left as-is.
#'
#' @param template Character string. The `user_prompt_template` from prompts.csv.
#' @param trial    One-row data frame or named list from trials.csv.
#' @return Filled prompt string.
fill_prompt <- function(template, trial) {
  orientation <- trial[["orientation"]]
  dirs <- DIRECTION_WORDS[[orientation]]
  if (is.null(dirs)) stop("Unknown orientation: ", orientation)

  out <- template
  out <- gsub("{direction_a}", dirs$a, out, fixed = TRUE)
  out <- gsub("{direction_b}", dirs$b, out, fixed = TRUE)
  out <- gsub("{test_a_shape}", trial[["test_a_shape"]], out, fixed = TRUE)
  out <- gsub("{test_b_shape}", trial[["test_b_shape"]], out, fixed = TRUE)
  out
}

# =============================================================================
# Response parser
# =============================================================================

#' Extract a structured response_larger value from raw model text.
#'
#' Maps directional words (left/right/top/bottom/upper-left/lower-right) to
#' "a" or "b" based on the trial's orientation, then normalises to the
#' canonical set: "a", "b", "equal", "unknown", "parse_error".
#'
#' For chain-of-thought prompts the function first looks for an explicit
#' "ANSWER: <word>" tag; if absent it falls back to scanning the full text.
#'
#' @param raw_response Character. Full verbatim model response.
#' @param orientation  Character. Trial orientation ("horizontal", "vertical",
#'   "diagonal").
#' @param response_format Character. Prompt's response_format field
#'   ("forced_choice" or "free_text").
#' @return One of: "a", "b", "equal", "unknown", "parse_error".
parse_response <- function(raw_response, orientation, response_format = "forced_choice") {
  if (is.null(raw_response) || is.na(raw_response) || nchar(trimws(raw_response)) == 0) {
    return("parse_error")
  }

  dirs <- DIRECTION_WORDS[[orientation]]
  if (is.null(dirs)) stop("Unknown orientation: ", orientation)

  # For chain-of-thought, prefer the explicit ANSWER tag
  text <- raw_response
  if (response_format == "free_text") {
    answer_match <- regmatches(text, regexpr("(?i)ANSWER\\s*:\\s*(\\S+)", text, perl = TRUE))
    if (length(answer_match) > 0 && nchar(answer_match) > 0) {
      text <- sub("(?i).*ANSWER\\s*:\\s*(\\S+).*", "\\1", answer_match, perl = TRUE)
    }
  }

  # Normalise: lowercase, strip punctuation (keep hyphens and spaces), split words
  text_clean <- tolower(trimws(text))
  text_clean <- gsub("[^a-z -]", " ", text_clean)
  text_clean <- trimws(text_clean)
  words <- strsplit(text_clean, "\\s+")[[1]]
  first_word <- words[1]
  # For compound directions like "upper left" -> "upper-left"
  first_two <- if (length(words) >= 2) paste(words[1:2], collapse = "-") else ""

  # Map to canonical answer
  if (is.na(first_word) || first_word == "") return("parse_error")

  if (first_word == dirs$a || first_two == dirs$a || first_word == "a") return("a")
  if (first_word == dirs$b || first_two == dirs$b || first_word == "b") return("b")
  if (first_word %in% c("equal", "same", "neither")) return("equal")
  if (first_word %in% c("unknown", "unsure", "unclear", "cannot", "can't", "not")) return("unknown")

  # Fallback: scan full cleaned text for any direction word (try both hyphenated and spaced)
  full_clean <- tolower(gsub("[^a-z -]", " ", raw_response))
  dir_a_pat <- paste0(gsub("-", "[ -]", dirs$a, fixed = TRUE))
  dir_b_pat <- paste0(gsub("-", "[ -]", dirs$b, fixed = TRUE))
  if (grepl(dir_a_pat, full_clean)) return("a")
  if (grepl(dir_b_pat, full_clean)) return("b")
  if (grepl("equal|same|neither", full_clean))  return("equal")
  if (grepl("unknown|unsure|unclear",  full_clean)) return("unknown")

  "parse_error"
}

# =============================================================================
# Dataset builder
# =============================================================================

#' Build a vitals-compatible dataset from trials and a single prompt variant.
#'
#' Each row represents one (trial, prompt) pair. The `input` column contains
#' the filled user prompt, `target` contains the ground truth answer, and
#' metadata columns carry everything needed by the solver and scorer.
#'
#' @param trials    Data frame from trials.csv.
#' @param prompt    One-row data frame from prompts.csv.
#' @param image_dir Directory with answer-stripped images.
#' @return A tibble suitable for `Task$new(dataset = ...)`.
build_dataset <- function(trials, prompt, image_dir = "images_eval") {
  tibble(
    id              = as.character(trials$trial_id),
    input           = vapply(
      seq_len(nrow(trials)),
      function(i) fill_prompt(prompt$user_prompt_template, trials[i, ]),
      character(1)
    ),
    target          = trials$true_larger,
    # Metadata for solver and scorer
    trial_id        = trials$trial_id,
    orientation     = trials$orientation,
    tier            = trials$tier,
    true_diff_ratio = trials$true_diff_ratio,
    prompt_id       = prompt$prompt_id,
    response_format = prompt$response_format,
    image_path      = file.path(
      image_dir,
      paste0(trials$trial_id, ".", trials$file_format)
    )
  )
}

# =============================================================================
# Custom solver
# =============================================================================

#' Create an Ebbinghaus solver that sends image + text to a VLM.
#'
#' Returns a solver function compatible with vitals `Task$new(solver = ...)`.
#' The solver reads image paths from the dataset (passed via `image_paths`
#' argument) and sends each image alongside the text prompt to the model.
#'
#' @param solver_chat An ellmer Chat object (will be cloned per sample).
#' @return A solver function.
ebbinghaus_solver <- function(inputs, ..., solver_chat, image_paths) {

  # Build one chat clone per sample and send image + text
  chats <- map2(inputs, image_paths, function(prompt_text, img_path) {
    ch <- solver_chat$clone()
    ch$chat(prompt_text, content_image_file(img_path, resize = "none"))
    ch
  })

  list(
    result      = map_chr(chats, function(ch) ch$last_turn()@text),
    solver_chat = chats
  )
}

# =============================================================================
# Custom scorer
# =============================================================================

#' Score Ebbinghaus evaluation results using deterministic parsing.
#'
#' Parses each raw model response using `parse_response()`, compares to
#' `target`, and returns an ordered factor (I/C). Stores parsed responses
#' in `scorer_metadata`.
#'
#' @param samples Tibble from `task$get_samples()` — includes `result`,
#'   `target`, `orientation`, `response_format`.
#' @return A list with `score` (ordered factor) and `scorer_metadata`.
ebbinghaus_scorer <- function(samples) {

  parsed <- pmap_chr(
    list(samples$result, samples$orientation, samples$response_format),
    function(result, orientation, response_format) {
      parse_response(result, orientation, response_format)
    }
  )

  correct <- (parsed == samples$target)

  scores <- factor(
    ifelse(correct, "C", "I"),
    levels  = c("I", "C"),
    ordered = TRUE
  )

  list(
    score           = scores,
    scorer_metadata = tibble(
      parsed_response = parsed,
      correct         = correct
    )
  )
}

# =============================================================================
# Chat constructor helper
# =============================================================================

#' Create an ellmer Chat for a model config + system prompt.
#'
#' @param model_cfg Named list with `provider`, `model`, and optionally
#'   `temperature`, `max_tokens`.
#' @param system_prompt Character: system prompt string.
#' @return An ellmer Chat object.
make_chat <- function(model_cfg, system_prompt) {
  p <- params(
    temperature = model_cfg$temperature %||% 0,
    max_tokens  = model_cfg$max_tokens  %||% 512L
  )

  switch(model_cfg$provider,
    anthropic = chat_anthropic(
      system_prompt = system_prompt, model = model_cfg$model, params = p
    ),
    openai = chat_openai(
      system_prompt = system_prompt, model = model_cfg$model, params = p
    ),
    google = chat_google_gemini(
      system_prompt = system_prompt, model = model_cfg$model, params = p
    ),
    github = chat_github(
      system_prompt = system_prompt, model = model_cfg$model, params = p
    ),
    stop("Unknown provider: ", model_cfg$provider,
         ". Use 'anthropic', 'openai', 'google', or 'github'.")
  )
}

# =============================================================================
# High-level orchestration
# =============================================================================

#' Run the full evaluation across prompts × models.
#'
#' Creates one vitals Task per (prompt, model) combination, evaluates it,
#' and returns a named list of Task objects. Use `vitals_bind()` on the
#' result to get a combined data frame for analysis.
#'
#' @param trials    Data frame from trials.csv.
#' @param prompts   Data frame from prompts.csv.
#' @param models    List of named lists. Each must have `provider` and `model`;
#'   optionally `temperature`, `max_tokens`. Example:
#'   `list(provider = "openai", model = "gpt-5.4-pro")`.
#' @param image_dir Directory containing answer-stripped images. If the
#'   directory doesn't exist, images will be stripped from `images/`.
#' @param epochs    Number of times to repeat each sample (default 1).
#' @param view      Open the Inspect log viewer after each eval (default:
#'   only at the end, not after each task).
#'
#' @return A named list of Task objects. Names follow the pattern
#'   `"<provider>/<model>__<prompt_description>"`.
run_evals <- function(trials,
                      prompts,
                      models,
                      image_dir = "images_eval",
                      epochs    = 1L,
                      view      = FALSE) {

  # Strip answers from images if needed
  if (!dir.exists(image_dir) || length(list.files(image_dir)) == 0) {
    message("Stripping answers from images...")
    strip_answer_from_images(trials, image_dir)
  }

  tasks <- list()

  for (mi in seq_along(models)) {
    mcfg <- models[[mi]]
    model_label <- paste0(mcfg$provider, "/", mcfg$model)

    for (p_idx in seq_len(nrow(prompts))) {
      prompt <- prompts[p_idx, ]
      task_name <- paste0(model_label, "__", prompt$description)

      message(sprintf("Creating task: %s", task_name))

      dataset <- build_dataset(trials, prompt, image_dir)
      chat    <- make_chat(mcfg, prompt$system_prompt)

      task <- Task$new(
        dataset = dataset,
        solver  = ebbinghaus_solver,
        scorer  = ebbinghaus_scorer,
        epochs  = epochs,
        name    = task_name
      )

      message(sprintf("Evaluating: %s", task_name))

      task$eval(
        solver_chat = chat,
        image_paths = dataset$image_path,
        view        = view
      )

      tasks[[task_name]] <- task
    }
  }

  message("All evaluations complete. ", length(tasks), " tasks evaluated.")
  message("Use vitals_view() to open the Inspect log viewer.")

  invisible(tasks)
}

# =============================================================================
# Results extraction
# =============================================================================

#' Extract evaluation results from tasks into a flat data frame.
#'
#' Combines all Task objects via `vitals_bind()` and unnests metadata
#' columns needed for downstream analysis. This is the primary bridge
#' between vitals output and `analyze_results()`.
#'
#' @param tasks Named list of Task objects (as returned by `run_evals()`).
#' @return A tibble with columns: task, id, score, trial_id, orientation,
#'   tier, true_diff_ratio, prompt_id, parsed_response, correct,
#'   model_label, prompt_description.
extract_results <- function(tasks) {
  bound <- do.call(vitals_bind, tasks)

  # Parse task name to extract model and prompt info
  bound$model_label <- sub("__.*$", "", bound$task)
  bound$prompt_description <- sub("^.*__", "", bound$task)

  bound
}
