# =============================================================================
# analyze.R — Phase 3: Analysis
# =============================================================================
# Joins evaluation results with trial and prompt metadata, computes metrics,
# and generates plots.
#
# Supports two input modes:
#   1. vitals Tasks (primary): pass a list of Task objects from run_evals()
#   2. Legacy CSV (backward-compatible): pass paths to evals.csv
#
# Usage:
#   source("R/analyze.R")  # also sources R/evaluate.R
#
#   # From vitals tasks:
#   results <- analyze_results(tasks = tasks)
#
#   # From CSV files (legacy):
#   results <- analyze_results(
#     evals_path   = "data/evals.csv",
#     trials_path  = "data/trials.csv",
#     prompts_path = "data/prompts.csv"
#   )
# =============================================================================

library(dplyr)
library(tidyr)
library(ggplot2)

source("R/evaluate.R")

# =============================================================================
# Data ingestion
# =============================================================================

#' Load and join data from vitals tasks or legacy CSV files.
#'
#' @param tasks       Named list of vitals Task objects (from run_evals()).
#' @param trials_path Path to trials.csv (used for metadata enrichment).
#' @param prompts_path Path to prompts.csv (used for metadata enrichment).
#' @param evals_path  Path to legacy evals.csv (only used if tasks is NULL).
#' @return A tibble with all columns needed for analysis.
load_eval_data <- function(tasks        = NULL,
                           trials_path  = "data/trials.csv",
                           prompts_path = "data/prompts.csv",
                           evals_path   = NULL) {

  if (!is.null(tasks) && !is.null(evals_path)) {
    stop("Provide `tasks` or `evals_path`, not both.")
  }
  if (is.null(tasks) && is.null(evals_path)) {
    stop("Provide either `tasks` (vitals Task objects) or `evals_path` (CSV).")
  }

  trials  <- read.csv(trials_path, stringsAsFactors = FALSE)
  prompts <- read.csv(prompts_path, stringsAsFactors = FALSE)

  if (!is.null(tasks)) {
    # --- vitals path ---
    data <- extract_results(tasks)

    data <- data |>
      left_join(
        trials |> select(trial_id, test_a_shape, test_b_shape,
                         surround_a_size, surround_b_size,
                         surround_a_n, surround_b_n,
                         canvas_width, canvas_height,
                         orientation, true_larger, true_diff_ratio, tier),
        by = c("id" = "trial_id")
      ) |>
      left_join(
        prompts |> select(prompt_id, description),
        by = "prompt_id"
      )

    data <- data |>
      mutate(
        correct = (score == "C"),
        parsed_response = NA_character_,
        illusion_susceptible = if_else(tier == 1, score == "I", NA),
        illusion_direction = NA_character_
      )

    if ("metadata" %in% names(data)) {
      tryCatch({
        meta <- hoist(data, metadata, "scorer_metadata")
        if ("scorer_metadata" %in% names(meta)) {
          parsed <- purrr::map_chr(
            meta$scorer_metadata,
            function(m) {
              if (is.data.frame(m) && "parsed_response" %in% names(m)) {
                m$parsed_response[1]
              } else {
                NA_character_
              }
            }
          )
          data$parsed_response <- parsed
          data$illusion_direction <- if_else(
            data$tier == 1 & data$parsed_response %in% c("a", "b"),
            data$parsed_response,
            NA_character_
          )
        }
      }, error = function(e) {
        message("Note: Could not extract scorer_metadata: ", e$message)
      })
    }

  } else if (!is.null(evals_path)) {
    # --- Legacy CSV path ---
    evals <- read.csv(evals_path, stringsAsFactors = FALSE)

    data <- evals |>
      left_join(trials, by = "trial_id") |>
      left_join(prompts, by = "prompt_id") |>
      mutate(
        correct = (response_larger == true_larger),
        model_label = paste0(provider, "/", model),
        prompt_description = description,
        parsed_response = response_larger,
        illusion_susceptible = if_else(tier == 1, response_larger != "equal", NA),
        illusion_direction = if_else(
          tier == 1 & response_larger %in% c("a", "b"),
          response_larger,
          NA_character_
        )
      )

  }

  data
}

# =============================================================================
# d-prime computation
# =============================================================================

#' Compute d-prime (signal detection sensitivity) per model.
#'
#' Treats "a" or "b" trials as signal-present (model must detect which is
#' larger) and "equal" trials as signal-absent (model should say "equal").
#'   - Hit:  correctly identifies the larger shape on unequal trials
#'   - FA:   says a or b on equal trials (false alarm)
#'
#' Applies Hautus (1995) log-linear correction: adds 0.5 to hit/FA counts
#' and 1 to totals to avoid infinite d-prime from 0% or 100% rates.
#'
#' @param data Joined evaluation data frame.
#' @return A tibble with model_label, hit_rate, fa_rate, dprime.
compute_dprime <- function(data) {

  has_equal <- any(data$tier == 1, na.rm = TRUE)
  has_unequal <- any(data$tier != 1, na.rm = TRUE)
  if (!has_equal || !has_unequal) return(tibble())

  hit_data <- data |>
    filter(true_larger %in% c("a", "b"), !is.na(parsed_response)) |>
    group_by(model_label) |>
    summarise(
      hits    = sum(parsed_response == true_larger),
      n_signal = n(),
      .groups = "drop"
    )

  fa_data <- data |>
    filter(true_larger == "equal", !is.na(parsed_response)) |>
    group_by(model_label) |>
    summarise(
      fas      = sum(parsed_response %in% c("a", "b")),
      n_noise  = n(),
      .groups  = "drop"
    )

  dprime <- hit_data |>
    inner_join(fa_data, by = "model_label") |>
    mutate(
      # Log-linear correction (Hautus 1995)
      hit_rate = (hits + 0.5) / (n_signal + 1),
      fa_rate  = (fas + 0.5)  / (n_noise + 1),
      dprime   = qnorm(hit_rate) - qnorm(fa_rate)
    )

  dprime
}

# =============================================================================
# Main analysis function
# =============================================================================

#' Analyze evaluation results
#'
#' Computes accuracy and bias metrics and generates key plots. All outputs
#' (plots as PNG, tables as CSV) are saved to `output_dir`.
#'
#' @param tasks       Named list of vitals Task objects (from run_evals()).
#'   If NULL, falls back to reading from CSV files.
#' @param trials_path  Path to trials.csv
#' @param evals_path   Path to legacy evals.csv (only if tasks is NULL)
#' @param prompts_path Path to prompts.csv
#' @param output_dir   Directory for plots and summary tables
#' @return List with: $data (joined data frame), $metrics (summary stats),
#'   $plots (list of ggplot objects)
analyze_results <- function(tasks        = NULL,
                            trials_path  = "data/trials.csv",
                            evals_path   = NULL,
                            prompts_path = "data/prompts.csv",
                            output_dir   = "output") {

  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  data <- load_eval_data(
    tasks        = tasks,
    trials_path  = trials_path,
    prompts_path = prompts_path,
    evals_path   = evals_path
  )

  # =========================================================================
  # Metrics
  # =========================================================================

  # --- Overall accuracy by model ---
  accuracy_by_model <- data |>
    filter(!is.na(correct)) |>
    group_by(model_label) |>
    summarise(n = n(), accuracy = mean(correct), .groups = "drop")

  # --- Accuracy by model × tier ---
  accuracy_by_model_tier <- data |>
    filter(!is.na(correct)) |>
    group_by(model_label, tier) |>
    summarise(n = n(), accuracy = mean(correct), .groups = "drop")

  # --- Accuracy by prompt variant ---
  accuracy_by_prompt <- data |>
    filter(!is.na(correct)) |>
    group_by(prompt_description, model_label) |>
    summarise(n = n(), accuracy = mean(correct), .groups = "drop")

  # --- Accuracy by prompt × tier ---
  accuracy_by_prompt_tier <- data |>
    filter(!is.na(correct)) |>
    group_by(prompt_description, model_label, tier) |>
    summarise(n = n(), accuracy = mean(correct), .groups = "drop")

  # --- Illusion susceptibility (Tier 1) ---
  illusion_susceptibility_rate <- data |>
    filter(tier == 1, !is.na(illusion_susceptible)) |>
    group_by(model_label) |>
    summarise(
      n = n(),
      susceptibility = mean(illusion_susceptible),
      .groups = "drop"
    )

  # --- Illusion direction (Tier 1: which side does the model favor?) ---
  illusion_direction_rate <- data |>
    filter(tier == 1, !is.na(illusion_direction)) |>
    group_by(model_label, illusion_direction) |>
    summarise(n = n(), .groups = "drop") |>
    group_by(model_label) |>
    mutate(prop = n / sum(n)) |>
    ungroup()

  # --- Spatial bias (overall) ---
  spatial_bias <- data |>
    filter(parsed_response %in% c("a", "b")) |>
    group_by(model_label, parsed_response) |>
    summarise(n = n(), .groups = "drop") |>
    group_by(model_label) |>
    mutate(prop = n / sum(n)) |>
    ungroup()

  # --- Spatial bias by orientation ---
  spatial_bias_by_orientation <- data |>
    filter(parsed_response %in% c("a", "b")) |>
    group_by(model_label, orientation, parsed_response) |>
    summarise(n = n(), .groups = "drop") |>
    group_by(model_label, orientation) |>
    mutate(prop = n / sum(n)) |>
    ungroup()

  # --- Congruency effect (Tier 2 vs Tier 3) ---
  congruency_effect <- data |>
    filter(tier %in% c(2, 3), !is.na(correct)) |>
    group_by(model_label, tier) |>
    summarise(accuracy = mean(correct), .groups = "drop") |>
    pivot_wider(names_from = tier, values_from = accuracy, names_prefix = "tier_") |>
    mutate(congruency_effect = tier_3 - tier_2)

  # --- Confusion matrix (true_larger vs parsed_response) ---
  confusion <- data |>
    filter(!is.na(parsed_response), !is.na(true_larger)) |>
    group_by(model_label, true_larger, parsed_response) |>
    summarise(n = n(), .groups = "drop")

  # --- d-prime ---
  dprime <- compute_dprime(data)

  # --- Conditional: temperature effects ---
  temperature_effect <- NULL
  if ("temperature" %in% names(data) &&
      n_distinct(data$temperature, na.rm = TRUE) > 1) {
    temperature_effect <- data |>
      filter(!is.na(correct)) |>
      group_by(model_label, temperature) |>
      summarise(n = n(), accuracy = mean(correct), .groups = "drop")
  }

  # --- Conditional: format effects ---
  format_effect <- NULL
  if ("file_format" %in% names(data) &&
      n_distinct(data$file_format, na.rm = TRUE) > 1) {
    format_effect <- data |>
      filter(!is.na(correct)) |>
      group_by(model_label, file_format) |>
      summarise(n = n(), accuracy = mean(correct), .groups = "drop")
  }

  # --- Conditional: confidence calibration ---
  confidence_calibration <- NULL
  if ("response_confidence" %in% names(data) &&
      any(!is.na(data$response_confidence))) {
    confidence_calibration <- data |>
      filter(!is.na(response_confidence), !is.na(correct)) |>
      mutate(conf_bin = cut(
        response_confidence,
        breaks = c(0, 0.25, 0.50, 0.75, 1.0),
        labels = c("0-25%", "25-50%", "50-75%", "75-100%"),
        include.lowest = TRUE
      )) |>
      group_by(model_label, conf_bin) |>
      summarise(n = n(), accuracy = mean(correct), .groups = "drop")
  }

  metrics <- list(
    accuracy_by_model           = accuracy_by_model,
    accuracy_by_model_tier      = accuracy_by_model_tier,
    accuracy_by_prompt          = accuracy_by_prompt,
    accuracy_by_prompt_tier     = accuracy_by_prompt_tier,
    illusion_susceptibility     = illusion_susceptibility_rate,
    illusion_direction          = illusion_direction_rate,
    spatial_bias                = spatial_bias,
    spatial_bias_by_orientation = spatial_bias_by_orientation,
    congruency_effect           = congruency_effect,
    confusion                   = confusion,
    dprime                      = dprime,
    temperature_effect          = temperature_effect,
    format_effect               = format_effect,
    confidence_calibration      = confidence_calibration
  )

  # =========================================================================
  # Plots
  # =========================================================================

  plots <- list()

  # --- 1. Overall accuracy by model ---
  plots$accuracy_overall <- ggplot(
    accuracy_by_model,
    aes(y = reorder(model_label, accuracy), x = accuracy)
  ) +
    geom_col() +
    geom_text(aes(label = sprintf("%.2f", accuracy)), hjust = -0.1, size = 3) +
    xlim(0, 1) +
    labs(title = "Overall Accuracy by Model", y = NULL, x = "Accuracy") +
    theme_minimal()

  # --- 2. Accuracy by tier ---
  plots$accuracy_by_tier <- ggplot(
    accuracy_by_model_tier,
    aes(x = factor(tier), y = accuracy, fill = model_label)
  ) +
    geom_col(position = "dodge") +
    geom_text(
      aes(label = sprintf("%.2f", accuracy)),
      position = position_dodge(width = 0.9), vjust = -0.5, size = 3
    ) +
    ylim(0, 1) +
    labs(title = "Accuracy by Difficulty Tier",
         x = "Tier", y = "Accuracy", fill = "Model") +
    theme_minimal()

  # --- 3. Psychometric curve ---
  psych_data <- data |>
    filter(!is.na(correct), true_diff_ratio > 0) |>
    mutate(diff_bin = cut(
      true_diff_ratio,
      breaks = c(0, 0.10, 0.20, 0.30, 1.0),
      labels = c("0-10%", "10-20%", "20-30%", ">30%")
    )) |>
    group_by(model_label, diff_bin) |>
    summarise(
      n = n(),
      accuracy = mean(correct),
      se = sqrt(accuracy * (1 - accuracy) / n),
      .groups = "drop"
    )

  plots$psychometric_curve <- ggplot(
    psych_data,
    aes(x = diff_bin, y = accuracy, color = model_label, group = model_label)
  ) +
    geom_point(size = 3) +
    geom_line() +
    geom_errorbar(
      aes(ymin = pmax(0, accuracy - se), ymax = pmin(1, accuracy + se)),
      width = 0.2
    ) +
    ylim(0, 1) +
    labs(title = "Psychometric Curve: Accuracy vs Size Difference",
         x = "True Size Difference", y = "Accuracy", color = "Model") +
    theme_minimal()

  # --- 4. Illusion susceptibility ---
  if (nrow(illusion_susceptibility_rate) > 0) {
    plots$illusion_susceptibility <- ggplot(
      illusion_susceptibility_rate,
      aes(y = reorder(model_label, susceptibility), x = susceptibility)
    ) +
      geom_col() +
      geom_text(aes(label = sprintf("%.2f", susceptibility)), hjust = -0.1, size = 3) +
      xlim(0, 1) +
      labs(title = "Illusion Susceptibility (Tier 1: Equal Sizes)",
           subtitle = "Proportion of trials where model answered non-equal",
           y = NULL, x = "Susceptibility Rate") +
      theme_minimal()
  }

  # --- 5. Illusion direction ---
  if (nrow(illusion_direction_rate) > 0) {
    plots$illusion_direction <- ggplot(
      illusion_direction_rate,
      aes(x = model_label, y = prop, fill = illusion_direction)
    ) +
      geom_col(position = "dodge") +
      geom_text(
        aes(label = sprintf("%.2f", prop)),
        position = position_dodge(width = 0.9), vjust = -0.5, size = 3
      ) +
      labs(title = "Illusion Direction (Tier 1: Which Side Does the Model Favor?)",
           subtitle = "Among fooled responses on equal-size trials",
           x = NULL, y = "Proportion", fill = "Chose") +
      theme_minimal() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
  }

  # --- 6. Confusion matrix heatmap ---
  plots$confusion_matrix <- ggplot(
    confusion,
    aes(x = parsed_response, y = true_larger, fill = n)
  ) +
    geom_tile() +
    geom_text(aes(label = n), size = 3) +
    scale_fill_gradient(low = "white", high = "steelblue") +
    facet_wrap(~model_label) +
    labs(title = "Confusion Matrix: True vs Predicted",
         x = "Model Response", y = "Ground Truth", fill = "Count") +
    theme_minimal()

  # --- 7. Spatial bias ---
  plots$spatial_bias <- ggplot(
    spatial_bias,
    aes(x = model_label, y = prop, fill = parsed_response)
  ) +
    geom_col(position = "dodge") +
    geom_text(
      aes(label = sprintf("%.2f", prop)),
      position = position_dodge(width = 0.9), vjust = -0.5, size = 3
    ) +
    labs(title = "Spatial Bias: Preference for A vs B",
         x = NULL, y = "Proportion", fill = "Response") +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  # --- 8. Spatial bias by orientation ---
  if (nrow(spatial_bias_by_orientation) > 0) {
    plots$spatial_bias_by_orientation <- ggplot(
      spatial_bias_by_orientation,
      aes(x = model_label, y = prop, fill = parsed_response)
    ) +
      geom_col(position = "dodge") +
      facet_wrap(~orientation) +
      labs(title = "Spatial Bias by Orientation",
           x = NULL, y = "Proportion", fill = "Response") +
      theme_minimal() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
  }

  # --- 9. Prompt comparison ---
  plots$prompt_comparison <- ggplot(
    accuracy_by_prompt,
    aes(x = prompt_description, y = accuracy, fill = model_label)
  ) +
    geom_col(position = "dodge") +
    geom_text(
      aes(label = sprintf("%.2f", accuracy)),
      position = position_dodge(width = 0.9), vjust = -0.5, size = 3
    ) +
    ylim(0, 1) +
    labs(title = "Accuracy by Prompt Variant",
         x = NULL, y = "Accuracy", fill = "Model") +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  # --- 10. Prompt comparison faceted by tier ---
  plots$prompt_comparison_by_tier <- ggplot(
    accuracy_by_prompt_tier,
    aes(x = prompt_description, y = accuracy, fill = model_label)
  ) +
    geom_col(position = "dodge") +
    facet_wrap(~tier, labeller = labeller(tier = function(x) paste("Tier", x))) +
    ylim(0, 1) +
    labs(title = "Accuracy by Prompt Variant and Tier",
         x = NULL, y = "Accuracy", fill = "Model") +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  # --- 11. Congruency effect ---
  if (nrow(congruency_effect) > 0) {
    plots$congruency_effect <- ggplot(
      congruency_effect,
      aes(x = model_label, y = congruency_effect)
    ) +
      geom_col() +
      geom_hline(yintercept = 0, linetype = "dashed") +
      geom_text(aes(label = sprintf("%.2f", congruency_effect)), vjust = -0.5, size = 3) +
      labs(title = "Congruency Effect (Tier 3 - Tier 2 Accuracy)",
           subtitle = "Positive = better when illusion reinforces truth",
           x = NULL, y = "Effect Size") +
      theme_minimal() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
  }

  # --- 12. d-prime ---
  if (nrow(dprime) > 0) {
    plots$dprime <- ggplot(
      dprime,
      aes(y = reorder(model_label, dprime), x = dprime)
    ) +
      geom_col() +
      geom_text(aes(label = sprintf("%.2f", dprime)), hjust = -0.1, size = 3) +
      labs(title = "d-prime (Perceptual Sensitivity)",
           subtitle = "Higher = better at distinguishing unequal from equal sizes",
           y = NULL, x = "d'") +
      theme_minimal()
  }

  # --- Conditional: temperature effects ---
  if (!is.null(temperature_effect)) {
    plots$temperature_effect <- ggplot(
      temperature_effect,
      aes(x = factor(temperature), y = accuracy, fill = model_label)
    ) +
      geom_col(position = "dodge") +
      ylim(0, 1) +
      labs(title = "Accuracy by Temperature",
           x = "Temperature", y = "Accuracy", fill = "Model") +
      theme_minimal()
  }

  # --- Conditional: format effects ---
  if (!is.null(format_effect)) {
    plots$format_effect <- ggplot(
      format_effect,
      aes(x = file_format, y = accuracy, fill = model_label)
    ) +
      geom_col(position = "dodge") +
      ylim(0, 1) +
      labs(title = "Accuracy by File Format",
           x = "Format", y = "Accuracy", fill = "Model") +
      theme_minimal()
  }

  # --- Conditional: confidence calibration ---
  if (!is.null(confidence_calibration)) {
    plots$confidence_calibration <- ggplot(
      confidence_calibration,
      aes(x = conf_bin, y = accuracy, color = model_label, group = model_label)
    ) +
      geom_point(size = 3) +
      geom_line() +
      geom_abline(slope = 1 / 4, intercept = -0.125, linetype = "dashed", alpha = 0.3) +
      ylim(0, 1) +
      labs(title = "Confidence Calibration",
           subtitle = "Dashed line = perfect calibration",
           x = "Reported Confidence", y = "Actual Accuracy", color = "Model") +
      theme_minimal()
  }

  # =========================================================================
  # Save outputs
  # =========================================================================

  # Save all plots
  for (pname in names(plots)) {
    p <- plots[[pname]]
    if (!is.null(p)) {
      ggsave(
        file.path(output_dir, paste0(pname, ".png")), p,
        width = 8, height = 5
      )
    }
  }

  # Save summary tables
  save_csv <- function(df, name) {
    if (!is.null(df) && nrow(df) > 0) {
      write.csv(df, file.path(output_dir, paste0(name, ".csv")), row.names = FALSE)
    }
  }

  save_csv(accuracy_by_model,           "accuracy_by_model")
  save_csv(accuracy_by_model_tier,      "accuracy_by_model_tier")
  save_csv(accuracy_by_prompt,          "accuracy_by_prompt")
  save_csv(accuracy_by_prompt_tier,     "accuracy_by_prompt_tier")
  save_csv(illusion_susceptibility_rate, "illusion_susceptibility")
  save_csv(illusion_direction_rate,     "illusion_direction")
  save_csv(spatial_bias,                "spatial_bias")
  save_csv(spatial_bias_by_orientation, "spatial_bias_by_orientation")
  save_csv(congruency_effect,           "congruency_effect")
  save_csv(confusion,                   "confusion_matrix")
  save_csv(dprime,                      "dprime")
  save_csv(temperature_effect,          "temperature_effect")
  save_csv(format_effect,               "format_effect")
  save_csv(confidence_calibration,      "confidence_calibration")

  message("Analysis complete. Plots and tables saved to: ", output_dir)

  list(
    data    = data,
    metrics = metrics,
    plots   = plots
  )
}
