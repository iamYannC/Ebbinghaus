# =============================================================================
# evaluate.R — Phase 2: Evaluation Pipeline
# =============================================================================
# Provides:
#   evaluate_trial()   — send one image + prompt to a VLM, return a result row
#   evaluate_all()     — iterate over trials × prompts × model configs,
#                        append results to evals.csv
#   parse_response()   — extract response_larger from raw model text
#   fill_prompt()      — resolve prompt templates for a given trial
#
# API keys are read from environment variables:
#   ANTHROPIC_API_KEY, OPENAI_API_KEY, GOOGLE_API_KEY
#
# Usage:
#   source("R/evaluate.R")
#
#   model_cfg <- list(
#     provider      = "openai",
#     model         = "gpt-4o",
#     model_version = NA,
#     temperature   = 0,
#     max_tokens    = 512
#   )
#
#   results <- evaluate_all(
#     trials   = read.csv("data/trials.csv"),
#     prompts  = read.csv("data/prompts.csv"),
#     models   = list(model_cfg),
#     out_path = "data/evals.csv"
#   )
# =============================================================================

library(httr2)
library(jsonlite)
library(base64enc)

# =============================================================================
# Direction helpers
# =============================================================================

# Map orientation to the direction words used in prompts for positions A and B.
# These match the convention in trials: A = left/top/upper-left.
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

  # Normalise: lowercase, strip punctuation, take first word
  text_clean <- tolower(trimws(text))
  text_clean <- gsub("[^a-z -]", " ", text_clean)   # keep hyphens (upper-left)
  text_clean <- trimws(text_clean)
  first_word <- strsplit(text_clean, "\\s+")[[1]][1]

  # Map to canonical answer
  if (is.na(first_word) || first_word == "") return("parse_error")

  if (first_word == dirs$a || first_word == "a")    return("a")
  if (first_word == dirs$b || first_word == "b")    return("b")
  if (first_word %in% c("equal", "same", "neither")) return("equal")
  if (first_word %in% c("unknown", "unsure", "unclear", "cannot", "can't", "not")) return("unknown")

  # Fallback: scan full cleaned text for any direction word
  full_clean <- tolower(gsub("[^a-z -]", " ", raw_response))
  if (grepl(dirs$a, full_clean, fixed = TRUE)) return("a")
  if (grepl(dirs$b, full_clean, fixed = TRUE)) return("b")
  if (grepl("equal|same|neither", full_clean))  return("equal")
  if (grepl("unknown|unsure|unclear",  full_clean)) return("unknown")

  "parse_error"
}

# =============================================================================
# Image encoding
# =============================================================================

#' Read an image file and return its base64-encoded string and MIME type.
#'
#' @param image_path Path to the image file.
#' @return Named list: $b64 (base64 string), $mime (MIME type string).
encode_image <- function(image_path) {
  ext  <- tolower(tools::file_ext(image_path))
  mime <- switch(ext,
    png  = "image/png",
    jpg  = , jpeg = "image/jpeg",
    webp = "image/webp",
    svg  = "image/svg+xml",
    stop("Unsupported image format: ", ext)
  )
  raw_bytes <- readBin(image_path, what = "raw", n = file.info(image_path)$size)
  b64 <- base64encode(raw_bytes)
  list(b64 = b64, mime = mime)
}

# =============================================================================
# Provider-specific API callers
# =============================================================================

#' Call Anthropic Messages API with an image.
#'
#' @param image_path Path to the stimulus image.
#' @param system_prompt System prompt string.
#' @param user_prompt  Filled user prompt string.
#' @param model        Model ID (e.g. "claude-opus-4-5").
#' @param temperature  Sampling temperature.
#' @param max_tokens   Max tokens for response.
#' @return Named list: $text (raw response text), $error (NA or message).
.call_anthropic <- function(image_path, system_prompt, user_prompt,
                             model, temperature, max_tokens) {
  api_key <- Sys.getenv("ANTHROPIC_API_KEY")
  if (nchar(api_key) == 0) stop("ANTHROPIC_API_KEY not set")

  img <- encode_image(image_path)

  body <- list(
    model      = model,
    max_tokens = max_tokens,
    temperature = temperature,
    system     = system_prompt,
    messages   = list(
      list(
        role    = "user",
        content = list(
          list(
            type  = "image",
            source = list(
              type       = "base64",
              media_type = img$mime,
              data       = img$b64
            )
          ),
          list(type = "text", text = user_prompt)
        )
      )
    )
  )

  resp <- request("https://api.anthropic.com/v1/messages") |>
    req_headers(
      "x-api-key"         = api_key,
      "anthropic-version" = "2023-06-01",
      "content-type"      = "application/json"
    ) |>
    req_body_json(body) |>
    req_retry(
      max_tries        = 4,
      retry_on_failure = TRUE,
      is_transient     = \(r) resp_status(r) %in% c(429, 500, 503, 529)
    ) |>
    req_perform()

  parsed <- resp_body_json(resp)
  text   <- parsed$content[[1]]$text
  list(text = text, error = NA_character_)
}

#' Call OpenAI Chat Completions API with an image.
.call_openai <- function(image_path, system_prompt, user_prompt,
                          model, temperature, max_tokens) {
  api_key <- Sys.getenv("OPENAI_API_KEY")
  if (nchar(api_key) == 0) stop("OPENAI_API_KEY not set")

  img <- encode_image(image_path)
  data_url <- paste0("data:", img$mime, ";base64,", img$b64)

  body <- list(
    model       = model,
    temperature = temperature,
    max_tokens  = max_tokens,
    messages    = list(
      list(role = "system", content = system_prompt),
      list(
        role    = "user",
        content = list(
          list(type = "image_url", image_url = list(url = data_url)),
          list(type = "text",      text = user_prompt)
        )
      )
    )
  )

  resp <- request("https://api.openai.com/v1/chat/completions") |>
    req_headers(
      "Authorization" = paste("Bearer", api_key),
      "Content-Type"  = "application/json"
    ) |>
    req_body_json(body) |>
    req_retry(
      max_tries        = 4,
      retry_on_failure = TRUE,
      is_transient     = \(r) resp_status(r) %in% c(429, 500, 503)
    ) |>
    req_perform()

  parsed <- resp_body_json(resp)
  text   <- parsed$choices[[1]]$message$content
  list(text = text, error = NA_character_)
}

#' Call Google Gemini API with an image.
.call_google <- function(image_path, system_prompt, user_prompt,
                          model, temperature, max_tokens) {
  api_key <- Sys.getenv("GOOGLE_API_KEY")
  if (nchar(api_key) == 0) stop("GOOGLE_API_KEY not set")

  img <- encode_image(image_path)

  body <- list(
    system_instruction = list(
      parts = list(list(text = system_prompt))
    ),
    contents = list(
      list(
        role  = "user",
        parts = list(
          list(
            inline_data = list(
              mime_type = img$mime,
              data      = img$b64
            )
          ),
          list(text = user_prompt)
        )
      )
    ),
    generationConfig = list(
      temperature    = temperature,
      maxOutputTokens = max_tokens
    )
  )

  url <- paste0(
    "https://generativelanguage.googleapis.com/v1beta/models/",
    model, ":generateContent?key=", api_key
  )

  resp <- request(url) |>
    req_headers("Content-Type" = "application/json") |>
    req_body_json(body) |>
    req_retry(
      max_tries        = 4,
      retry_on_failure = TRUE,
      is_transient     = \(r) resp_status(r) %in% c(429, 500, 503)
    ) |>
    req_perform()

  parsed <- resp_body_json(resp)
  text   <- parsed$candidates[[1]]$content$parts[[1]]$text
  list(text = text, error = NA_character_)
}

# =============================================================================
# Core evaluation function
# =============================================================================

#' Evaluate a single trial with one prompt and one model configuration.
#'
#' Sends the stimulus image to the VLM API, parses the response, and returns
#' a one-row data frame conforming to the evals.csv schema.
#'
#' @param trial      One-row data frame from trials.csv.
#' @param prompt     One-row data frame from prompts.csv.
#' @param provider   Character: "anthropic", "openai", or "google".
#' @param model      Character: model identifier as used by the provider API.
#' @param model_version Character or NA: optional version label.
#' @param temperature Numeric: sampling temperature.
#' @param max_tokens  Integer: max response tokens.
#' @param image_dir   Character: directory containing eval images (answer-stripped).
#'   Defaults to "images_eval/". Falls back to trial$file_path if the eval
#'   copy doesn't exist (useful for local testing).
#' @param eval_id     Integer: identifier for this row. NA = caller assigns.
#'
#' @return A one-row data frame with the evals.csv schema.
evaluate_trial <- function(trial, prompt,
                           provider, model,
                           model_version = NA_character_,
                           temperature   = 0,
                           max_tokens    = 512L,
                           image_dir     = "images_eval",
                           eval_id       = NA_integer_) {

  # Resolve image path: prefer answer-stripped copy
  stripped_name <- paste0(trial$trial_id, ".", trial$file_format)
  stripped_path <- file.path(image_dir, stripped_name)
  image_path <- if (file.exists(stripped_path)) stripped_path else trial$file_path

  # Fill prompt template
  user_prompt <- fill_prompt(prompt$user_prompt_template, trial)

  # Call the appropriate provider
  t_start <- proc.time()[["elapsed"]]

  result <- tryCatch({
    caller <- switch(provider,
      anthropic = .call_anthropic,
      openai    = .call_openai,
      google    = .call_google,
      stop("Unknown provider: ", provider)
    )
    caller(
      image_path    = image_path,
      system_prompt = prompt$system_prompt,
      user_prompt   = user_prompt,
      model         = model,
      temperature   = temperature,
      max_tokens    = max_tokens
    )
  }, error = function(e) {
    list(text = NA_character_, error = conditionMessage(e))
  })

  latency_ms <- as.integer(round((proc.time()[["elapsed"]] - t_start) * 1000))

  # Parse response
  response_larger <- if (!is.na(result$error)) {
    "parse_error"
  } else {
    parse_response(result$text, trial$orientation, prompt$response_format)
  }

  data.frame(
    eval_id            = as.integer(eval_id),
    trial_id           = trial$trial_id,
    prompt_id          = prompt$prompt_id,
    provider           = provider,
    model              = model,
    model_version      = as.character(model_version),
    temperature        = temperature,
    max_tokens         = as.integer(max_tokens),
    response_larger    = response_larger,
    response_confidence = NA_real_,
    raw_response       = if (is.na(result$error)) result$text else NA_character_,
    latency_ms         = latency_ms,
    timestamp          = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    error              = result$error,
    stringsAsFactors   = FALSE
  )
}

# =============================================================================
# Batch evaluator
# =============================================================================

#' Run evaluations across all combinations of trials × prompts × model configs.
#'
#' Results are appended to `out_path` (CSV) after each trial so that progress
#' is saved incrementally. Already-evaluated combinations are skipped if
#' `out_path` already exists (resume support).
#'
#' @param trials    Data frame: trials table (or filtered subset).
#' @param prompts   Data frame: prompts table.
#' @param models    List of named lists, each with fields:
#'                    provider, model, model_version (opt.), temperature, max_tokens.
#' @param out_path  Character: path to evals.csv output file.
#' @param image_dir Character: directory with answer-stripped images.
#' @param verbose   Logical: print progress messages.
#'
#' @return Invisibly returns the full evals data frame (loaded from out_path).
evaluate_all <- function(trials,
                         prompts,
                         models,
                         out_path  = "data/evals.csv",
                         image_dir = "images_eval",
                         verbose   = TRUE) {

  # Load existing results for resume support
  if (file.exists(out_path)) {
    existing <- read.csv(out_path, stringsAsFactors = FALSE)
    next_id  <- max(existing$eval_id, na.rm = TRUE) + 1L
    if (verbose) message("Resuming: ", nrow(existing), " evals already complete.")
  } else {
    existing <- NULL
    next_id  <- 1L
  }

  # Build the full job list: trials × prompts × models
  jobs <- expand.grid(
    trial_idx  = seq_len(nrow(trials)),
    prompt_idx = seq_len(nrow(prompts)),
    model_idx  = seq_along(models),
    stringsAsFactors = FALSE
  )

  # Filter out already-completed combinations
  if (!is.null(existing) && nrow(existing) > 0) {
    done_keys <- paste(existing$trial_id, existing$prompt_id,
                       existing$provider, existing$model, existing$temperature,
                       sep = "|")
    jobs$key <- with(jobs, {
      mapply(function(ti, pi, mi) {
        t  <- trials[ti, ]
        p  <- prompts[pi, ]
        m  <- models[[mi]]
        paste(t$trial_id, p$prompt_id, m$provider, m$model,
              m$temperature, sep = "|")
      }, trial_idx, prompt_idx, model_idx)
    })
    jobs <- jobs[!jobs$key %in% done_keys, ]
  }

  if (nrow(jobs) == 0) {
    if (verbose) message("All evaluations already complete.")
    return(invisible(existing))
  }

  if (verbose) message("Running ", nrow(jobs), " evaluations...")

  for (i in seq_len(nrow(jobs))) {
    trial  <- trials[jobs$trial_idx[i], ]
    prompt <- prompts[jobs$prompt_idx[i], ]
    mcfg   <- models[[jobs$model_idx[i]]]

    if (verbose) {
      message(sprintf(
        "[%d/%d] trial %d | prompt %d | %s/%s",
        i, nrow(jobs), trial$trial_id, prompt$prompt_id,
        mcfg$provider, mcfg$model
      ))
    }

    row <- evaluate_trial(
      trial         = trial,
      prompt        = prompt,
      provider      = mcfg$provider,
      model         = mcfg$model,
      model_version = mcfg$model_version %||% NA_character_,
      temperature   = mcfg$temperature   %||% 0,
      max_tokens    = mcfg$max_tokens    %||% 512L,
      image_dir     = image_dir,
      eval_id       = next_id
    )
    next_id <- next_id + 1L

    # Append to CSV incrementally
    write.table(row,
                file      = out_path,
                append    = file.exists(out_path),
                col.names = !file.exists(out_path),
                row.names = FALSE,
                sep       = ",",
                quote     = TRUE)
  }

  if (verbose) message("Done. Results written to: ", out_path)
  invisible(read.csv(out_path, stringsAsFactors = FALSE))
}

# =============================================================================
# Utility
# =============================================================================

# Null-coalescing operator (available in R >= 4.4, define for compatibility)
`%||%` <- function(x, y) if (!is.null(x)) x else y
