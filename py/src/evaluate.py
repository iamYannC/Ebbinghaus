"""
evaluate.py — Phase 2: Evaluation Pipeline (Inspect AI-based)

Evaluates VLM performance on the Ebbinghaus benchmark using Inspect AI
for structured logging, evaluation, and analysis.

Provides:
  build_dataset()         — construct Inspect AI samples from trials
  ebbinghaus_solver()     — custom solver: sends image + text to VLM
  ebbinghaus_scorer()     — custom scorer: deterministic parse + compare
  run_evals()             — high-level orchestration across prompts × models
  fill_prompt()           — resolve prompt template placeholders
  parse_response()        — extract canonical answer from raw model text

Uses Inspect AI for task orchestration. API keys are read from env vars:
  ANTHROPIC_API_KEY, OPENAI_API_KEY, GOOGLE_API_KEY

Usage:
  from src.evaluate import run_evals
  import pandas as pd

  trials  = pd.read_csv("data/trials.csv")
  prompts = pd.read_csv("data/prompts.csv")

  logs = run_evals(
      trials  = trials,
      prompts = prompts,
      models  = [
          {"provider": "openai",    "model": "gpt-5.4-pro"},
          {"provider": "anthropic", "model": "claude-sonnet-4-6"},
      ],
  )
"""

import os
import re
import pandas as pd
from inspect_ai import Task, eval as inspect_eval
from inspect_ai.dataset import Sample, MemoryDataset
from inspect_ai.model import ChatMessageUser, ContentImage, ContentText, get_model
from inspect_ai.scorer import Score, scorer, Target, CORRECT, INCORRECT
from inspect_ai.solver import Generate, TaskState, solver

from src.strip_answer import strip_answer_from_images


# =============================================================================
# Direction helpers
# =============================================================================

DIRECTION_WORDS = {
    "horizontal": {"a": "left",       "b": "right"},
    "vertical":   {"a": "top",        "b": "bottom"},
    "diagonal":   {"a": "upper-left", "b": "lower-right"},
}


def fill_prompt(template: str, trial: dict) -> str:
    """Fill prompt template placeholders for a specific trial.

    Replaces {direction_a}, {direction_b}, {test_a_shape}, {test_b_shape}
    with values from the trial.
    """
    orientation = trial["orientation"]
    dirs = DIRECTION_WORDS.get(orientation)
    if dirs is None:
        raise ValueError(f"Unknown orientation: {orientation}")

    out = template
    out = out.replace("{direction_a}", dirs["a"])
    out = out.replace("{direction_b}", dirs["b"])
    out = out.replace("{test_a_shape}", str(trial["test_a_shape"]))
    out = out.replace("{test_b_shape}", str(trial["test_b_shape"]))
    return out


# =============================================================================
# Response parser
# =============================================================================

def parse_response(
    raw_response: str,
    orientation: str,
    response_format: str = "forced_choice",
) -> str:
    """Extract a structured response_larger value from raw model text.

    Maps directional words to "a" or "b" based on the trial's orientation,
    then normalises to: "a", "b", "equal", "unknown", "parse_error".
    """
    if not raw_response or not raw_response.strip():
        return "parse_error"

    dirs = DIRECTION_WORDS.get(orientation)
    if dirs is None:
        raise ValueError(f"Unknown orientation: {orientation}")

    # For chain-of-thought, prefer the explicit ANSWER tag
    text = raw_response
    if response_format == "free_text":
        match = re.search(r"(?i)ANSWER\s*:\s*(\S+)", text)
        if match:
            text = match.group(1)

    # Normalise: lowercase, strip punctuation (keep hyphens and spaces)
    text_clean = re.sub(r"[^a-z \-]", " ", text.lower().strip()).strip()
    words = text_clean.split()
    first_word = words[0] if words else ""
    first_two = "-".join(words[:2]) if len(words) >= 2 else ""

    if not first_word:
        return "parse_error"

    if first_word == dirs["a"] or first_two == dirs["a"] or first_word == "a":
        return "a"
    if first_word == dirs["b"] or first_two == dirs["b"] or first_word == "b":
        return "b"
    if first_word in ("equal", "same", "neither"):
        return "equal"
    if first_word in ("unknown", "unsure", "unclear", "cannot", "can't", "not"):
        return "unknown"

    # Fallback: scan full text
    full_clean = re.sub(r"[^a-z \-]", " ", raw_response.lower())
    dir_a_pat = dirs["a"].replace("-", "[ -]")
    dir_b_pat = dirs["b"].replace("-", "[ -]")
    if re.search(dir_a_pat, full_clean):
        return "a"
    if re.search(dir_b_pat, full_clean):
        return "b"
    if re.search(r"equal|same|neither", full_clean):
        return "equal"
    if re.search(r"unknown|unsure|unclear", full_clean):
        return "unknown"

    return "parse_error"


# =============================================================================
# Dataset builder
# =============================================================================

def build_dataset(
    trials: pd.DataFrame, prompt: pd.Series, image_dir: str = "images_eval"
) -> list[Sample]:
    """Build Inspect AI samples from trials and a single prompt variant.

    Each Sample represents one (trial, prompt) pair.
    """
    samples = []
    for i in range(len(trials)):
        row = trials.iloc[i]
        filled = fill_prompt(prompt["user_prompt_template"], row.to_dict())
        img_path = os.path.join(
            image_dir, f"{int(row['trial_id'])}.{row['file_format']}"
        )

        samples.append(Sample(
            input=[ChatMessageUser(content=[
                ContentImage(image=img_path),
                ContentText(text=filled),
            ])],
            target=row["true_larger"],
            id=str(int(row["trial_id"])),
            metadata={
                "trial_id": int(row["trial_id"]),
                "orientation": row["orientation"],
                "tier": int(row["tier"]) if pd.notna(row["tier"]) else None,
                "true_diff_ratio": row["true_diff_ratio"],
                "prompt_id": prompt["prompt_id"],
                "response_format": prompt["response_format"],
            },
        ))

    return samples


# =============================================================================
# Custom solver
# =============================================================================

@solver
def ebbinghaus_solver():
    """Solver that passes through the image + text to the model."""
    async def solve(state: TaskState, generate: Generate) -> TaskState:
        return await generate(state)
    return solve


# =============================================================================
# Custom scorer
# =============================================================================

@scorer(metrics=["accuracy"])
def ebbinghaus_scorer():
    """Score Ebbinghaus evaluation results using deterministic parsing."""
    async def score(state: TaskState, target: Target) -> Score:
        raw = state.output.completion
        orientation = state.metadata.get("orientation", "horizontal")
        response_format = state.metadata.get("response_format", "forced_choice")

        parsed = parse_response(raw, orientation, response_format)
        correct = parsed == target.text

        return Score(
            value=CORRECT if correct else INCORRECT,
            answer=parsed,
            metadata={
                "parsed_response": parsed,
                "correct": correct,
            },
        )
    return score


# =============================================================================
# High-level orchestration
# =============================================================================

def run_evals(
    trials: pd.DataFrame,
    prompts: pd.DataFrame,
    models: list[dict],
    image_dir: str = "images_eval",
    epochs: int = 1,
) -> list:
    """Run the full evaluation across prompts × models.

    Creates one Inspect AI Task per (prompt, model) combination, evaluates it,
    and returns a list of eval logs.

    Args:
        trials: DataFrame from trials.csv.
        prompts: DataFrame from prompts.csv.
        models: List of dicts with 'provider', 'model', optionally
            'temperature', 'max_tokens'.
        image_dir: Directory containing answer-stripped images.
        epochs: Number of times to repeat each sample.

    Returns:
        A list of Inspect AI eval log objects.
    """
    # Strip answers from images if needed
    if not os.path.isdir(image_dir) or not os.listdir(image_dir):
        print("Stripping answers from images...")
        strip_answer_from_images(trials, image_dir)

    all_logs = []

    for mcfg in models:
        model_label = f"{mcfg['provider']}/{mcfg['model']}"
        model_str = f"{mcfg['provider']}/{mcfg['model']}"

        for p_idx in range(len(prompts)):
            prompt = prompts.iloc[p_idx]
            task_name = f"{model_label}__{prompt['description']}"
            print(f"Creating task: {task_name}")

            samples = build_dataset(trials, prompt, image_dir)
            dataset = MemoryDataset(samples=samples, name=task_name)

            task = Task(
                dataset=dataset,
                solver=ebbinghaus_solver(),
                scorer=ebbinghaus_scorer(),
                epochs=epochs,
            )

            print(f"Evaluating: {task_name}")

            model_kwargs = {}
            if "temperature" in mcfg:
                model_kwargs["temperature"] = mcfg["temperature"]
            if "max_tokens" in mcfg:
                model_kwargs["max_tokens"] = mcfg["max_tokens"]

            logs = inspect_eval(
                task,
                model=get_model(model_str, **model_kwargs),
            )
            all_logs.extend(logs)

    print(f"All evaluations complete. {len(all_logs)} logs generated.")
    return all_logs
