# =============================================================================
# analyze.R — Phase 3: Analysis
# =============================================================================
# Joins trials + evals + prompts, computes metrics, generates plots.
#
# Usage:
#   source("R/analyze.R")
#   results <- analyze_results()
#   
#   # Or with custom paths:
#   results <- analyze_results(
#     trials_path = "data/trials.csv",
#     evals_path  = "data/evals.csv",
#     prompts_path = "data/prompts.csv",
#     output_dir  = "output"
#   )
# =============================================================================

library(dplyr)
library(ggplot2)

#' Analyze evaluation results
#'
#' Joins trials, evals, and prompts; computes accuracy and bias metrics;
#' generates key plots.
#'
#' @param trials_path Path to trials.csv
#' @param evals_path  Path to evals.csv
#' @param prompts_path Path to prompts.csv
#' @param output_dir  Directory for plots and summary tables
#' @return List with: $data (joined data frame), $metrics (summary stats),
#'   $plots (list of ggplot objects)
analyze_results <- function(trials_path  = "data/trials.csv",
                            evals_path   = "data/evals.csv",
                            prompts_path = "data/prompts.csv",
                            output_dir   = "output") {
  
  # Create output directory
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  
  # Load data
  trials  <- read.csv(trials_path, stringsAsFactors = FALSE)
  evals   <- read.csv(evals_path, stringsAsFactors = FALSE)
  prompts <- read.csv(prompts_path, stringsAsFactors = FALSE)
  
  # Join
  data <- evals |>
    left_join(trials, by = "trial_id") |>
    left_join(prompts, by = "prompt_id")
  
  # Compute derived columns
  data <- data |>
    mutate(
      # Correctness
      correct = (response_larger == true_larger),
      
      # Illusion susceptibility (Tier 1 only: equal sizes)
      illusion_susceptible = if_else(
        tier == 1,
        response_larger != "equal",
        NA
      ),
      
      # Illusion direction (Tier 1 only: which side did model pick?)
      illusion_direction = if_else(
        tier == 1 & response_larger %in% c("a", "b"),
        response_larger,
        NA_character_
      ),
      
      # Model label for plots
      model_label = paste0(provider, "/", model)
    )
  
  # --- Metrics ---
  
  # Overall accuracy by model and tier
  accuracy_by_model_tier <- data |>
    filter(!is.na(correct)) |>
    group_by(model_label, tier) |>
    summarise(
      n = n(),
      accuracy = mean(correct),
      .groups = "drop"
    )
  
  # Overall accuracy by model (across all tiers)
  accuracy_by_model <- data |>
    filter(!is.na(correct)) |>
    group_by(model_label) |>
    summarise(
      n = n(),
      accuracy = mean(correct),
      .groups = "drop"
    )
  
  # Accuracy by prompt
  accuracy_by_prompt <- data |>
    filter(!is.na(correct)) |>
    group_by(description, model_label) |>
    summarise(
      n = n(),
      accuracy = mean(correct),
      .groups = "drop"
    )
  
  # Illusion susceptibility (Tier 1 only)
  illusion_susceptibility_rate <- data |>
    filter(tier == 1, !is.na(illusion_susceptible)) |>
    group_by(model_label) |>
    summarise(
      n = n(),
      susceptibility = mean(illusion_susceptible),
      .groups = "drop"
    )
  
  # Spatial bias (does model favor A or B regardless of truth?)
  spatial_bias <- data |>
    filter(response_larger %in% c("a", "b")) |>
    group_by(model_label, response_larger) |>
    summarise(n = n(), .groups = "drop") |>
    group_by(model_label) |>
    mutate(prop = n / sum(n)) |>
    ungroup()
  
  # Congruency effect (Tier 2 vs Tier 3)
  congruency_effect <- data |>
    filter(tier %in% c(2, 3), !is.na(correct)) |>
    group_by(model_label, tier) |>
    summarise(accuracy = mean(correct), .groups = "drop") |>
    tidyr::pivot_wider(names_from = tier, values_from = accuracy, names_prefix = "tier_") |>
    mutate(congruency_effect = tier_3 - tier_2)  # Positive = better on congruent
  
  metrics <- list(
    accuracy_by_model = accuracy_by_model,
    accuracy_by_model_tier = accuracy_by_model_tier,
    accuracy_by_prompt = accuracy_by_prompt,
    illusion_susceptibility = illusion_susceptibility_rate,
    spatial_bias = spatial_bias,
    congruency_effect = congruency_effect
  )
  
  # --- Plots ---
  
  # 1. Overall accuracy by model
  p1 <- ggplot(accuracy_by_model, aes(x = reorder(model_label, accuracy), y = accuracy)) +
    geom_col(fill = "steelblue") +
    geom_text(aes(label = sprintf("%.2f", accuracy)), hjust = -0.1, size = 3) +
    coord_flip() +
    ylim(0, 1) +
    labs(title = "Overall Accuracy by Model",
         x = NULL, y = "Accuracy") +
    theme_minimal()
  
  # 2. Accuracy by tier (faceted by model if multiple models)
  p2 <- ggplot(accuracy_by_model_tier, aes(x = factor(tier), y = accuracy, fill = model_label)) +
    geom_col(position = "dodge") +
    geom_text(aes(label = sprintf("%.2f", accuracy)), 
              position = position_dodge(width = 0.9), vjust = -0.5, size = 3) +
    ylim(0, 1) +
    labs(title = "Accuracy by Difficulty Tier",
         x = "Tier", y = "Accuracy", fill = "Model") +
    theme_minimal()
  
  # 3. Psychometric curve (accuracy vs true_diff_ratio)
  psych_data <- data |>
    filter(!is.na(correct), true_diff_ratio > 0) |>  # Exclude equal trials
    mutate(diff_bin = cut(true_diff_ratio, breaks = c(0, 0.10, 0.20, 0.30, 1.0), 
                          labels = c("0-10%", "10-20%", "20-30%", ">30%"))) |>
    group_by(model_label, diff_bin) |>
    summarise(
      n = n(),
      accuracy = mean(correct),
      se = sqrt(accuracy * (1 - accuracy) / n),
      .groups = "drop"
    )
  
  p3 <- ggplot(psych_data, aes(x = diff_bin, y = accuracy, color = model_label, group = model_label)) +
    geom_point(size = 3) +
    geom_line() +
    geom_errorbar(aes(ymin = pmax(0, accuracy - se), ymax = pmin(1, accuracy + se)), width = 0.2) +
    ylim(0, 1) +
    labs(title = "Psychometric Curve: Accuracy vs Size Difference",
         x = "True Size Difference", y = "Accuracy", color = "Model") +
    theme_minimal()
  
  # 4. Illusion susceptibility (Tier 1)
  if (nrow(illusion_susceptibility_rate) > 0) {
    p4 <- ggplot(illusion_susceptibility_rate, aes(x = reorder(model_label, susceptibility), y = susceptibility)) +
      geom_col(fill = "coral") +
      geom_text(aes(label = sprintf("%.2f", susceptibility)), hjust = -0.1, size = 3) +
      coord_flip() +
      ylim(0, 1) +
      labs(title = "Illusion Susceptibility (Tier 1: Equal Sizes)",
           subtitle = "Proportion of trials where model answered non-equal",
           x = NULL, y = "Susceptibility Rate") +
      theme_minimal()
  } else {
    p4 <- NULL
  }
  
  # 5. Spatial bias
  p5 <- ggplot(spatial_bias, aes(x = model_label, y = prop, fill = response_larger)) +
    geom_col(position = "dodge") +
    geom_text(aes(label = sprintf("%.2f", prop)), 
              position = position_dodge(width = 0.9), vjust = -0.5, size = 3) +
    labs(title = "Spatial Bias: Preference for A vs B",
         x = NULL, y = "Proportion", fill = "Response") +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  
  # 6. Prompt comparison
  p6 <- ggplot(accuracy_by_prompt, aes(x = description, y = accuracy, fill = model_label)) +
    geom_col(position = "dodge") +
    geom_text(aes(label = sprintf("%.2f", accuracy)), 
              position = position_dodge(width = 0.9), vjust = -0.5, size = 3) +
    ylim(0, 1) +
    labs(title = "Accuracy by Prompt Variant",
         x = NULL, y = "Accuracy", fill = "Model") +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  
  # 7. Congruency effect (Tier 2 vs Tier 3)
  if (nrow(congruency_effect) > 0) {
    p7 <- ggplot(congruency_effect, aes(x = model_label, y = congruency_effect)) +
      geom_col(fill = "darkgreen") +
      geom_hline(yintercept = 0, linetype = "dashed") +
      geom_text(aes(label = sprintf("%.2f", congruency_effect)), vjust = -0.5, size = 3) +
      labs(title = "Congruency Effect (Tier 3 Accuracy - Tier 2 Accuracy)",
           subtitle = "Positive = better when illusion reinforces truth",
           x = NULL, y = "Effect Size") +
      theme_minimal() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
  } else {
    p7 <- NULL
  }
  
  plots <- list(
    accuracy_overall = p1,
    accuracy_by_tier = p2,
    psychometric_curve = p3,
    illusion_susceptibility = p4,
    spatial_bias = p5,
    prompt_comparison = p6,
    congruency_effect = p7
  )
  
  # Save plots
  ggsave(file.path(output_dir, "accuracy_overall.png"), p1, width = 8, height = 5)
  ggsave(file.path(output_dir, "accuracy_by_tier.png"), p2, width = 8, height = 5)
  ggsave(file.path(output_dir, "psychometric_curve.png"), p3, width = 8, height = 5)
  if (!is.null(p4)) ggsave(file.path(output_dir, "illusion_susceptibility.png"), p4, width = 8, height = 5)
  ggsave(file.path(output_dir, "spatial_bias.png"), p5, width = 8, height = 5)
  ggsave(file.path(output_dir, "prompt_comparison.png"), p6, width = 8, height = 5)
  if (!is.null(p7)) ggsave(file.path(output_dir, "congruency_effect.png"), p7, width = 8, height = 5)
  
  # Save summary tables
  write.csv(accuracy_by_model, file.path(output_dir, "accuracy_by_model.csv"), row.names = FALSE)
  write.csv(accuracy_by_model_tier, file.path(output_dir, "accuracy_by_model_tier.csv"), row.names = FALSE)
  write.csv(accuracy_by_prompt, file.path(output_dir, "accuracy_by_prompt.csv"), row.names = FALSE)
  write.csv(illusion_susceptibility_rate, file.path(output_dir, "illusion_susceptibility.csv"), row.names = FALSE)
  write.csv(spatial_bias, file.path(output_dir, "spatial_bias.csv"), row.names = FALSE)
  write.csv(congruency_effect, file.path(output_dir, "congruency_effect.csv"), row.names = FALSE)
  
  message("Analysis complete. Plots and tables saved to: ", output_dir)
  
  list(
    data = data,
    metrics = metrics,
    plots = plots
  )
}
