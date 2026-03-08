"""
analyze.py — Phase 3: Analysis

Joins evaluation results with trial and prompt metadata, computes metrics,
and generates plots.

Supports two input modes:
  1. Inspect AI logs (primary): pass eval logs from run_evals()
  2. Legacy CSV (backward-compatible): pass path to evals.csv

Usage:
  from src.analyze import analyze_results

  # From Inspect AI logs:
  results = analyze_results(logs=logs)

  # From CSV (legacy):
  results = analyze_results(evals_path="data/evals.csv")
"""

import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from scipy.stats import norm

from src.evaluate import parse_response


# =============================================================================
# Data ingestion
# =============================================================================

def load_eval_data(
    logs=None,
    trials_path: str = "data/trials.csv",
    prompts_path: str = "data/prompts.csv",
    evals_path: str | None = None,
) -> pd.DataFrame:
    """Load and join data from Inspect AI logs or legacy CSV files.

    Args:
        logs: List of Inspect AI eval log objects (from run_evals()).
        trials_path: Path to trials.csv.
        prompts_path: Path to prompts.csv.
        evals_path: Path to legacy evals.csv (only if logs is None).

    Returns:
        A DataFrame with all columns needed for analysis.
    """
    if logs is not None and evals_path is not None:
        raise ValueError("Provide `logs` or `evals_path`, not both.")
    if logs is None and evals_path is None:
        raise ValueError("Provide either `logs` (Inspect AI logs) or `evals_path` (CSV).")

    trials = pd.read_csv(trials_path)
    prompts = pd.read_csv(prompts_path)

    if logs is not None:
        # --- Inspect AI path ---
        rows = []
        for log in logs:
            model_label = str(log.eval.model)
            for sample in log.samples:
                meta = sample.metadata or {}
                score_val = sample.scores.get("ebbinghaus_scorer", None) if sample.scores else None

                rows.append({
                    "trial_id": meta.get("trial_id"),
                    "orientation": meta.get("orientation"),
                    "tier": meta.get("tier"),
                    "true_diff_ratio": meta.get("true_diff_ratio"),
                    "prompt_id": meta.get("prompt_id"),
                    "response_format": meta.get("response_format"),
                    "model_label": model_label,
                    "raw_response": sample.output.completion if sample.output else "",
                    "parsed_response": score_val.answer if score_val else None,
                    "correct": score_val.value == "C" if score_val else None,
                    "target": sample.target,
                })

        data = pd.DataFrame(rows)

        # Join with trials and prompts
        data = data.merge(
            trials[["trial_id", "test_a_shape", "test_b_shape",
                     "surround_a_size", "surround_b_size",
                     "surround_a_n", "surround_b_n",
                     "canvas_width", "canvas_height",
                     "true_larger"]],
            on="trial_id", how="left",
        )
        data = data.merge(
            prompts[["prompt_id", "description"]],
            on="prompt_id", how="left",
        )
        data.rename(columns={"description": "prompt_description"}, inplace=True)

        data["illusion_susceptible"] = np.where(
            data["tier"] == 1,
            ~data["correct"],
            np.nan,
        )
        data["illusion_direction"] = np.where(
            (data["tier"] == 1) & data["parsed_response"].isin(["a", "b"]),
            data["parsed_response"],
            None,
        )

    else:
        # --- Legacy CSV path ---
        evals = pd.read_csv(evals_path)
        data = evals.merge(trials, on="trial_id", how="left")
        data = data.merge(prompts, on="prompt_id", how="left")

        data["correct"] = data["response_larger"] == data["true_larger"]
        data["model_label"] = data["provider"] + "/" + data["model"]
        data["prompt_description"] = data["description"]
        data["parsed_response"] = data["response_larger"]
        data["illusion_susceptible"] = np.where(
            data["tier"] == 1,
            data["response_larger"] != "equal",
            np.nan,
        )
        data["illusion_direction"] = np.where(
            (data["tier"] == 1) & data["response_larger"].isin(["a", "b"]),
            data["response_larger"],
            None,
        )

    return data


# =============================================================================
# d-prime computation
# =============================================================================

def compute_dprime(data: pd.DataFrame) -> pd.DataFrame:
    """Compute d-prime (signal detection sensitivity) per model.

    Uses Hautus (1995) log-linear correction.
    """
    has_equal = (data["tier"] == 1).any()
    has_unequal = (data["tier"] != 1).any()
    if not has_equal or not has_unequal:
        return pd.DataFrame()

    signal = data[data["true_larger"].isin(["a", "b"]) & data["parsed_response"].notna()]
    hit_data = signal.groupby("model_label").agg(
        hits=("parsed_response", lambda x: (x == signal.loc[x.index, "true_larger"]).sum()),
        n_signal=("parsed_response", "count"),
    ).reset_index()

    noise = data[(data["true_larger"] == "equal") & data["parsed_response"].notna()]
    fa_data = noise.groupby("model_label").agg(
        fas=("parsed_response", lambda x: x.isin(["a", "b"]).sum()),
        n_noise=("parsed_response", "count"),
    ).reset_index()

    dprime = hit_data.merge(fa_data, on="model_label", how="inner")
    dprime["hit_rate"] = (dprime["hits"] + 0.5) / (dprime["n_signal"] + 1)
    dprime["fa_rate"] = (dprime["fas"] + 0.5) / (dprime["n_noise"] + 1)
    dprime["dprime"] = norm.ppf(dprime["hit_rate"]) - norm.ppf(dprime["fa_rate"])

    return dprime


# =============================================================================
# Main analysis function
# =============================================================================

def analyze_results(
    logs=None,
    trials_path: str = "data/trials.csv",
    evals_path: str | None = None,
    prompts_path: str = "data/prompts.csv",
    output_dir: str = "output",
) -> dict:
    """Analyze evaluation results.

    Computes accuracy and bias metrics and generates key plots. All outputs
    (plots as PNG, tables as CSV) are saved to output_dir.

    Args:
        logs: List of Inspect AI eval log objects (from run_evals()).
        trials_path: Path to trials.csv.
        evals_path: Path to legacy evals.csv (only if logs is None).
        prompts_path: Path to prompts.csv.
        output_dir: Directory for plots and summary tables.

    Returns:
        Dict with: data, metrics, plots.
    """
    os.makedirs(output_dir, exist_ok=True)

    data = load_eval_data(
        logs=logs,
        trials_path=trials_path,
        prompts_path=prompts_path,
        evals_path=evals_path,
    )

    # =========================================================================
    # Metrics
    # =========================================================================

    valid = data[data["correct"].notna()]

    accuracy_by_model = (
        valid.groupby("model_label")
        .agg(n=("correct", "count"), accuracy=("correct", "mean"))
        .reset_index()
    )

    accuracy_by_model_tier = (
        valid.groupby(["model_label", "tier"])
        .agg(n=("correct", "count"), accuracy=("correct", "mean"))
        .reset_index()
    )

    accuracy_by_prompt = (
        valid.groupby(["prompt_description", "model_label"])
        .agg(n=("correct", "count"), accuracy=("correct", "mean"))
        .reset_index()
    )

    accuracy_by_prompt_tier = (
        valid.groupby(["prompt_description", "model_label", "tier"])
        .agg(n=("correct", "count"), accuracy=("correct", "mean"))
        .reset_index()
    )

    illusion = data[(data["tier"] == 1) & data["illusion_susceptible"].notna()]
    illusion_susceptibility_rate = (
        illusion.groupby("model_label")
        .agg(n=("illusion_susceptible", "count"), susceptibility=("illusion_susceptible", "mean"))
        .reset_index()
    ) if len(illusion) > 0 else pd.DataFrame()

    ill_dir = data[(data["tier"] == 1) & data["illusion_direction"].notna()]
    illusion_direction_rate = (
        ill_dir.groupby(["model_label", "illusion_direction"])
        .size().reset_index(name="n")
    ) if len(ill_dir) > 0 else pd.DataFrame()
    if len(illusion_direction_rate) > 0:
        totals = illusion_direction_rate.groupby("model_label")["n"].transform("sum")
        illusion_direction_rate["prop"] = illusion_direction_rate["n"] / totals

    ab_data = data[data["parsed_response"].isin(["a", "b"])]
    spatial_bias = (
        ab_data.groupby(["model_label", "parsed_response"])
        .size().reset_index(name="n")
    )
    if len(spatial_bias) > 0:
        totals = spatial_bias.groupby("model_label")["n"].transform("sum")
        spatial_bias["prop"] = spatial_bias["n"] / totals

    congruency = valid[valid["tier"].isin([2, 3])]
    congruency_effect = pd.DataFrame()
    if len(congruency) > 0:
        ce = (
            congruency.groupby(["model_label", "tier"])
            .agg(accuracy=("correct", "mean"))
            .reset_index()
            .pivot_table(index="model_label", columns="tier", values="accuracy")
        )
        if 2 in ce.columns and 3 in ce.columns:
            congruency_effect = pd.DataFrame({
                "model_label": ce.index,
                "tier_2": ce[2].values,
                "tier_3": ce[3].values,
                "congruency_effect": (ce[3] - ce[2]).values,
            })

    confusion = (
        data[data["parsed_response"].notna() & data["true_larger"].notna()]
        .groupby(["model_label", "true_larger", "parsed_response"])
        .size().reset_index(name="n")
    )

    dprime = compute_dprime(data)

    metrics = {
        "accuracy_by_model": accuracy_by_model,
        "accuracy_by_model_tier": accuracy_by_model_tier,
        "accuracy_by_prompt": accuracy_by_prompt,
        "accuracy_by_prompt_tier": accuracy_by_prompt_tier,
        "illusion_susceptibility": illusion_susceptibility_rate,
        "illusion_direction": illusion_direction_rate,
        "spatial_bias": spatial_bias,
        "congruency_effect": congruency_effect,
        "confusion": confusion,
        "dprime": dprime,
    }

    # =========================================================================
    # Plots
    # =========================================================================

    plots = {}

    # 1. Overall accuracy by model
    fig, ax = plt.subplots(figsize=(8, 5))
    ordered = accuracy_by_model.sort_values("accuracy")
    ax.barh(ordered["model_label"], ordered["accuracy"])
    for i, (_, row) in enumerate(ordered.iterrows()):
        ax.text(row["accuracy"] + 0.01, i, f"{row['accuracy']:.2f}", va="center")
    ax.set_xlim(0, 1)
    ax.set_xlabel("Accuracy")
    ax.set_title("Overall Accuracy by Model")
    plots["accuracy_overall"] = fig

    # 2. Accuracy by tier
    fig, ax = plt.subplots(figsize=(8, 5))
    tiers = sorted(accuracy_by_model_tier["tier"].dropna().unique())
    models_list = accuracy_by_model_tier["model_label"].unique()
    x = np.arange(len(tiers))
    width = 0.8 / max(len(models_list), 1)
    for i, m in enumerate(models_list):
        subset = accuracy_by_model_tier[accuracy_by_model_tier["model_label"] == m]
        vals = [subset[subset["tier"] == t]["accuracy"].values[0]
                if t in subset["tier"].values else 0 for t in tiers]
        ax.bar(x + i * width, vals, width, label=m)
    ax.set_xticks(x + width * (len(models_list) - 1) / 2)
    ax.set_xticklabels([f"Tier {int(t)}" for t in tiers])
    ax.set_ylim(0, 1)
    ax.set_ylabel("Accuracy")
    ax.set_title("Accuracy by Difficulty Tier")
    ax.legend()
    plots["accuracy_by_tier"] = fig

    # 3. Psychometric curve
    psych = valid[valid["true_diff_ratio"] > 0].copy()
    if len(psych) > 0:
        psych["diff_bin"] = pd.cut(
            psych["true_diff_ratio"],
            bins=[0, 0.10, 0.20, 0.30, 1.0],
            labels=["0-10%", "10-20%", "20-30%", ">30%"],
        )
        psych_agg = (
            psych.groupby(["model_label", "diff_bin"], observed=True)
            .agg(n=("correct", "count"), accuracy=("correct", "mean"))
            .reset_index()
        )
        psych_agg["se"] = np.sqrt(
            psych_agg["accuracy"] * (1 - psych_agg["accuracy"]) / psych_agg["n"]
        )

        fig, ax = plt.subplots(figsize=(8, 5))
        for m in psych_agg["model_label"].unique():
            sub = psych_agg[psych_agg["model_label"] == m]
            ax.errorbar(
                sub["diff_bin"], sub["accuracy"], yerr=sub["se"],
                marker="o", capsize=3, label=m,
            )
        ax.set_ylim(0, 1)
        ax.set_xlabel("True Size Difference")
        ax.set_ylabel("Accuracy")
        ax.set_title("Psychometric Curve: Accuracy vs Size Difference")
        ax.legend()
        plots["psychometric_curve"] = fig

    # 4. Illusion susceptibility
    if len(illusion_susceptibility_rate) > 0:
        fig, ax = plt.subplots(figsize=(8, 5))
        ordered = illusion_susceptibility_rate.sort_values("susceptibility")
        ax.barh(ordered["model_label"], ordered["susceptibility"])
        for i, (_, row) in enumerate(ordered.iterrows()):
            ax.text(row["susceptibility"] + 0.01, i, f"{row['susceptibility']:.2f}", va="center")
        ax.set_xlim(0, 1)
        ax.set_xlabel("Susceptibility Rate")
        ax.set_title("Illusion Susceptibility (Tier 1: Equal Sizes)")
        plots["illusion_susceptibility"] = fig

    # 5. Confusion matrix heatmap
    if len(confusion) > 0:
        for m in confusion["model_label"].unique():
            sub = confusion[confusion["model_label"] == m]
            pivot = sub.pivot_table(
                index="true_larger", columns="parsed_response", values="n", fill_value=0
            )
            fig, ax = plt.subplots(figsize=(6, 4))
            sns.heatmap(pivot, annot=True, fmt="d", cmap="Blues", ax=ax)
            ax.set_title(f"Confusion Matrix: {m}")
            ax.set_xlabel("Model Response")
            ax.set_ylabel("Ground Truth")
            plots[f"confusion_{m.replace('/', '_')}"] = fig

    # 6. d-prime
    if len(dprime) > 0:
        fig, ax = plt.subplots(figsize=(8, 5))
        ordered = dprime.sort_values("dprime")
        ax.barh(ordered["model_label"], ordered["dprime"])
        for i, (_, row) in enumerate(ordered.iterrows()):
            ax.text(row["dprime"] + 0.05, i, f"{row['dprime']:.2f}", va="center")
        ax.set_xlabel("d'")
        ax.set_title("d-prime (Perceptual Sensitivity)")
        plots["dprime"] = fig

    # =========================================================================
    # Save outputs
    # =========================================================================

    for pname, fig in plots.items():
        fig.savefig(os.path.join(output_dir, f"{pname}.png"), bbox_inches="tight")
        plt.close(fig)

    for mname, df in metrics.items():
        if isinstance(df, pd.DataFrame) and len(df) > 0:
            df.to_csv(os.path.join(output_dir, f"{mname}.csv"), index=False)

    print(f"Analysis complete. Plots and tables saved to: {output_dir}")

    return {"data": data, "metrics": metrics, "plots": plots}
