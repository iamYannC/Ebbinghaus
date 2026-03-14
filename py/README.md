# Ebbinghaus Benchmark - Python 🐍 <img src="https://raw.githubusercontent.com/iamYannC/Ebbinghaus/main/docs/hex.png" alt="Ebbinghause hex logo from url" align="right" height="150"/>

Python implementation of the [Ebbinghaus Illusion Benchmark](../README.md). Output writes to the same shared directories (`images/`, `data/`, `output/`) as the R version.

🔥Try the [Kaggle Notebook](https://www.kaggle.com/code/yanncohen/ebbinghaus-illusion-benchmark-python)  comparing [Gemma 3 4B](https://huggingface.co/google/gemma-3-4b-it) and [Qwen2-VL 2B](https://huggingface.co/Qwen/Qwen2-VL-2B-Instruct) via [Hugging Face](https://huggingface.co/) (free OS models).

[![DOI](https://raw.githubusercontent.com/iamYannC/Ebbinghaus/master/docs/doi.svg)](https://doi.org/10.5281/zenodo.18906801)
[![Python 3.11+](https://img.shields.io/badge/Python-3.11+-blue?logo=python)](https://www.python.org/)
[![Kaggle Dataset](https://img.shields.io/badge/Kaggle-Dataset-20BEFF?logo=kaggle)](https://www.kaggle.com/datasets/yanncohen/ebbinghaus-illusion-benchmark)
[![Kaggle Notebook](https://img.shields.io/badge/Kaggle-Notebook-20BEFF?logo=kaggle)](https://www.kaggle.com/code/yanncohen/ebbinghaus-illusion-benchmark-python)
[![License: CC BY 4.0](https://img.shields.io/badge/License-CC%20BY%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by/4.0/)
[![ORCID](https://img.shields.io/badge/ORCID-0009--0009--0509--3609-brightgreen?logo=orcid)](https://orcid.org/0009-0009-0509-3609)

## Setup

Requires Python 3.11+. Install dependencies with [uv](https://docs.astral.sh/uv/):

```bash
cd py
uv sync
```

Or with pip:

```bash
pip install .
```


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

# Phase 3: Analyze results (plots displayed, metrics in returned dict)
from src.analyze import analyze_results

results = analyze_results(logs=logs)  # or: analyze_results(evals_df=evals)
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

> **No Inspect AI?** Use the Kaggle notebook workflow: load your evals into a DataFrame and run `analyze_results(show_plots=False, evals_df=evals, ...)`, then browse plots via the notebook display cells.

## Phase 3: Analysis

| | |
|---|---|
| **Input** | Inspect AI logs, evals DataFrame, or legacy `evals.csv` |
| **Output** | Plots (displayed or saved to `output/`) + metric DataFrames in the returned dict |

```python
# Default: display plots inline and save PNGs to output/
results = analyze_results(logs=logs)

# From an in-memory DataFrame:
results = analyze_results(evals_df=evals)

# Suppress inline display (plots are still saved and available in results["plots"]):
results = analyze_results(logs=logs, show_plots=False)

# Skip saving to disk entirely:
results = analyze_results(logs=logs, output_dir=None)
```

Plots are always saved as PNGs to `output_dir` (default `"output/"`) and available in `results["plots"]`. Set `show_plots=False` to suppress inline display, or `output_dir=None` to skip saving to disk. Metric DataFrames (e.g., `results["metrics"]["accuracy_by_model"]`) are always returned in the result dict for inspection or export. Computed metrics include overall accuracy, accuracy by tier, psychometric curves, illusion susceptibility, spatial bias, congruency effects, d-prime, and more.

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

`data/`, `images/`, and `output/` are shared with R at the project root. `output/` is written by default (pass `output_dir=None` to skip). For the full module listing, see [`TECHNICAL_REFERENCE.md`](TECHNICAL_REFERENCE.md).

See the [root README](../README.md) for tier definitions and project overview.

---

## Reference Manual

For the full internal-function reference, see [`docs/py_reference_manual.pdf`](../docs/py_reference_manual.pdf).

## License & Citation

This project is licensed under [CC BY 4.0](LICENSE.md) - you are free to use, modify, and redistribute with attribution. See [`CITATION.cff`](CITATION.cff) or use the "Cite this repository" button on GitHub.

Visit my [website](https://iamyannc.github.io/Yann-dev) for contact information.
