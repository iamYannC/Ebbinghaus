# Ebbinghaus Benchmark — Python

Python implementation of the [Ebbinghaus Illusion Benchmark](../README.md). Uses `pandas`, `matplotlib`, and [Inspect AI](https://inspect.ai-safety-institute.org.uk/) for evaluation. Output writes to the same shared directories (`images/`, `data/`, `output/`) as the R version.

## Setup

Requires Python 3.11+. Install with [uv](https://docs.astral.sh/uv/):

```bash
cd py
uv sync
```

Or with pip:

```bash
cd py
pip install -e .
```

## Quick Start

```python
import sys; sys.path.insert(0, ".")

# Phase 1: Generate stimuli
from src.generate_design import generate_design
from src.render_stimuli import render_stimuli

trials = generate_design(seed=7042, n_per_tier=50)
render_stimuli(trials)
trials.to_csv("data/trials.csv", index=False)

# Phase 2: Evaluate models
import pandas as pd
from src.evaluate import run_evals

prompts = pd.read_csv("data/prompts.csv")
models = [{"provider": "openai", "model": "gpt-5.4-pro"}]
logs = run_evals(trials, prompts, models)

# Phase 3: Analyze results
from src.analyze import analyze_results

results = analyze_results(logs=logs)
```

## Phase 1: Stimulus Creation

| | |
|---|---|
| **Input** | `config/defaults.py` (parameter pools, size ranges, color palettes) |
| **Output** | `pandas.DataFrame` + rendered images in `images/` |

Edit `config/defaults.py` to customize shapes, sizes, orientations, colors, etc. All defaults mirror the R version.

## Phase 2: Evaluation

| | |
|---|---|
| **Input** | trials DataFrame, `data/prompts.csv`, model list, API keys (env vars) |
| **Output** | Inspect AI eval logs |

Uses Inspect AI's `Task`, `@solver`, and `@scorer` decorators. API keys are read from environment variables (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`).

> **Lightweight alternative:** If you prefer not to depend on Inspect AI, you can use a legacy CSV-based workflow by adapting `R/legacy/evaluate.R` patterns for Python.

## Phase 3: Analysis

| | |
|---|---|
| **Input** | Inspect AI logs (or legacy `evals.csv`) |
| **Output** | Plots and summary CSVs in `output/` |

```python
results = analyze_results(logs=logs)
# or: results = analyze_results(evals_path="data/evals.csv")
```

Computed metrics include overall accuracy, accuracy by tier, psychometric curves, illusion susceptibility, spatial bias, congruency effects, d-prime, and more.

## File Structure

```
py/
├── pyproject.toml              # Dependencies (uv / pip)
├── config/
│   └── defaults.py             # Configurable parameters
├── src/
│   ├── draw_shape.py           # Atomic shape drawing (matplotlib)
│   ├── draw_trial.py           # Compose full stimulus image
│   ├── verify_trial.py         # Compute ground truth
│   ├── classify_tier.py        # Assign difficulty tier
│   ├── generate_trial.py       # Generate single trial parameters
│   ├── generate_design.py      # Build complete design matrix
│   ├── render_stimuli.py       # Batch render to images/
│   ├── strip_answer.py         # Strip ground truth from filenames
│   ├── evaluate.py             # Inspect AI evaluation pipeline
│   └── analyze.py              # Metrics and plots
```

See the [root README](../README.md) for tier definitions and project overview, and `VARIABLE_REGISTRY.md` for the Python-specific variable reference.
