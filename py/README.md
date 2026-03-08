# Ebbinghaus Benchmark - Python <img src="../docs/hex.png" alt="Ebbinghause hex logo" align="right" height="150"/>

Python implementation of the [Ebbinghaus Illusion Benchmark](../README.md). Uses `pandas`, `matplotlib`, and [Inspect AI](https://inspect.ai-safety-institute.org.uk/) for evaluation. Output writes to the same shared directories (`images/`, `data/`, `output/`) as the R version.

[![DOI](https://zenodo.org/badge/1175680688.svg)](https://doi.org/10.5281/zenodo.18906801)

## Setup

Requires Python 3.11+. Install dependencies with [uv](https://docs.astral.sh/uv/):

```bash
cd py
uv sync
```

Or with pip:

```bash
pip install -r py/pyproject.toml
```

All scripts run from the project root (`Ebbinghaus/`), not from `py/`.

## Quick Start

```python
import sys; sys.path.insert(0, "py")

# Phase 1: Generate stimuli
from src.generate_design import generate_design
from src.render_stimuli import render_stimuli

trials = generate_design(seed=42, n_per_tier=5)
render_stimuli(trials)
trials.to_csv("data/trials.csv", index=False) # current trials.csv is from R

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
| **Input** | [`py/config/defaults.py`](config/defaults.py) (parameter pools, size ranges, color palettes) |
| **Output** | `pandas.DataFrame` + rendered images in `images/` |

Edit [`py/config/defaults.py`](config/defaults.py) to customize shapes, sizes, orientations, colors, etc. All defaults mirror the R version.

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
├── config/defaults.py              # Configurable parameters (mirrors R defaults)
├── src/
│   ├── generate_design.py          # Phase 1 — Build a complete design matrix
│   ├── render_stimuli.py           # Phase 1 — Batch render trial table to images
│   ├── evaluate.py                 # Phase 2 — Inspect AI evaluation pipeline
│   └── analyze.py                  # Phase 3 — Metrics and plots
```

`data/`, `images/`, and `output/` are shared with R at the project root. For the full module listing, see [`TECHNICAL_REFERENCE.md`](TECHNICAL_REFERENCE.md).

See the [root README](../README.md) for tier definitions and project overview.

---

## Reference Manual

For the full internal-function reference, see [`docs/py_reference_manual.pdf`](../docs/py_reference_manual.pdf).
