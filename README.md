# Ebbinghaus Illusion Benchmark <img src="https://raw.githubusercontent.com/iamYannC/Ebbinghaus/main/docs/hex.png" alt="Ebbinghause hex logo from url" align="right" height="150"/>

A flexible R & Python (and [Kaggle's Notebook](https://www.kaggle.com/code/yanncohen/ebbinghaus-illusion-benchmark-python)) for generating variants of the Ebbinghaus illusion and evaluating vision-language model (VLM) accuracy on them. The project provides a straightforward API for the common case while allowing full flexibility over every parameter. The **[trial table](data/trials.csv) is the single source of truth**: every stimulus image is fully determined by a row in this table.


[![DOI](https://raw.githubusercontent.com/iamYannC/Ebbinghaus/master/docs/doi.svg)](https://doi.org/10.5281/zenodo.18906801)
[![R](https://img.shields.io/badge/R-276DC3?logo=r&logoColor=white)](https://www.r-project.org/)
[![Kaggle Dataset](https://img.shields.io/badge/Kaggle-Dataset-20BEFF?logo=kaggle)](https://www.kaggle.com/datasets/yanncohen/ebbinghaus-illusion-benchmark)
[![Kaggle Notebook](https://img.shields.io/badge/Kaggle-Notebook-20BEFF?logo=kaggle)](https://www.kaggle.com/code/yanncohen/ebbinghaus-illusion-benchmark-python)
[![License: CC BY 4.0](https://img.shields.io/badge/License-CC%20BY%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by/4.0/)
[![ORCID](https://img.shields.io/badge/ORCID-0009--0009--0509--3609-brightgreen?logo=orcid)](https://orcid.org/0009-0009-0509-3609)

## Python Users 🐍
A complete [Python](https://github.com/iamYannC/Ebbinghaus/tree/main/py) version of the benchmark is also available.

🔥 [Kaggle Notebook](https://www.kaggle.com/code/yanncohen/ebbinghaus-illusion-benchmark-python) with [Gemma 3 4B](https://huggingface.co/google/gemma-3-4b-it) on a free GPU.

------------------------------------------------------------------------

## Quick Start

``` r
# Phase 1: Generate stimuli
source("config/defaults.R")
source("R/generate_design.R")
source("R/render_stimuli.R")

trials <- generate_design(seed = 42, n_per_tier = 5)
write.csv(trials, "data/trials.csv", row.names = FALSE) # optional, but not necessary for this workflow
render_stimuli(trials)

# Phase 2: Evaluate models
source("R/evaluate.R")
prompts <- read.csv("data/prompts.csv", stringsAsFactors = FALSE)
models  <- list(list(provider = "openai", model = "gpt-5.4-pro"))
tasks   <- run_evals(trials, prompts, models)

# Phase 3: Analyze results (plots displayed, metrics in global env)
source("R/analyze.R")
results <- analyze_results(tasks = tasks)
```

Phase 1 (stimulus creation) works standalone. Phase 2 requires API keys and the `vitals`/`ellmer` packages. Phase 3 is optional - a convenience layer for standard metrics and plots. See below for details on each phase.

------------------------------------------------------------------------

## Difficulty Tiers

Each trial is assigned a difficulty tier based on the relationship between test sizes and surrounding context shapes. The core illusion principle: **larger surrounds make the enclosed test shape appear smaller**.

| Tier | Name | Condition |
|-------------------|-------------------|----------------------------------|
| 0 | **Sanity check** | No surrounds. Just two shapes - can the model compare sizes at all? |
| 1 | **Classic illusion** | Test sizes are equal, surrounds differ. Pure illusion condition - the correct answer is "equal." |
| 2 | **Incongruent** | Test sizes differ, but surrounds push perception the wrong way. The truly larger shape has larger surrounds, making it appear smaller. |
| 3 | **Congruent** | Test sizes differ, and surrounds reinforce the truth. The truly larger shape has smaller surrounds, making it appear even larger. |

------------------------------------------------------------------------

## Phase 1: Stimulus Creation

Generates trial parameters and renders Ebbinghaus illusion images with known ground truth.

|  |  |
|------------------------------------|------------------------------------|
| **Input** | `config/defaults.R` (parameter pools, size ranges, color palettes) |
| **Output** | `trials` data frame + rendered images in `images/` |

``` r
source("config/defaults.R")
source("R/generate_design.R")
source("R/render_stimuli.R")

trials <- generate_design(seed = 42, n_per_tier = 5)
render_stimuli(trials)
```

This is the most basic use case: generate a balanced design with 5 trials per tier and render the images. To customize, edit `config/defaults.R` before generating (e.g., change shape pools, size ranges, canvas dimensions).

![Example stimuli generated with defaults edited to only produce horizontal layouts, circle shapes, on a white background](docs/stimuli-example.png)

The [trial table](data/trials.csv) can also be constructed by other means - filter an existing table, build one manually, or use any external tool. All downstream functions accept any data frame with the correct schema. See [`TECHNICAL_REFERENCE.md`](TECHNICAL_REFERENCE.md) for the full trials schema and configuration reference.

------------------------------------------------------------------------

## Phase 2: Evaluation

Sends stimulus images to LLMs and records their responses using the [vitals](https://vitals.tidyverse.org/) evaluation framework. A custom solver sends each image + prompt to the model; a deterministic scorer parses the response and compares to ground truth.

|  |  |
|------------------------------------|------------------------------------|
| **Input** | `trials` data frame, `data/prompts.csv`, model list, API keys (env vars) |
| **Output** | Named list of vitals `Task` objects (viewable with `vitals_view()`) |

``` r
source("R/evaluate.R")

trials  <- read.csv("data/trials.csv", stringsAsFactors = FALSE)
prompts <- read.csv("data/prompts.csv", stringsAsFactors = FALSE)

models <- list(
  list(provider = "openai",     model = "gpt-5.4-pro"),
  list(provider = "anthropic",  model = "claude-sonnet-4-6"),
  list(provider = "anthropic",  model = "claude-opus-4-6"), # within-provider comparison
  list(provider = "google",     model = "gemini-3.1-pro-preview")
)

tasks <- run_evals(trials, prompts, models)
```

Each (prompt, model) combination creates one vitals Task. Images are automatically stripped of ground-truth labels before sending. Prompt templates support placeholders (`{direction_a}`, `{direction_b}`, `{test_a_shape}`, `{test_b_shape}`) that are filled per trial based on orientation.

See [`TECHNICAL_REFERENCE.md`](TECHNICAL_REFERENCE.md) for the prompts schema and model configuration options.

> **Lightweight alternative:** If you prefer not to depend on `vitals` and `ellmer`, a legacy CSV-based evaluation workflow is available in `R/legacy/evaluate.R`. It writes results directly to `data/evals.csv` without the vitals framework.

------------------------------------------------------------------------

## Phase 3: Analysis

A complementary step that joins evaluation results with trial metadata, computes accuracy and bias metrics, and generates plots. This is provided as a convenience - researchers may prefer to write their own analysis.

|            |                                                              |
|------------------------------------|------------------------------------|
| **Input**  | vitals `Task` objects from Phase 2 (or a legacy `evals.csv`) |
| **Output** | Plots (displayed or saved to `output/`) + metric data frames in the global environment |

``` r
source("R/analyze.R")

# Default: display plots interactively, metric data frames assigned to global env
results <- analyze_results(tasks = tasks)

# Alternative: save plots as PNGs instead of displaying
results <- analyze_results(tasks = tasks, show_plots = FALSE)
```

By default, plots are printed to the graphics device for interactive viewing. Set `show_plots = FALSE` to save them as PNGs to `output/` instead. Metric data frames (e.g., `accuracy_by_model`, `dprime`, `spatial_bias`) are assigned to the global environment so you can inspect or export them as needed. See [`TECHNICAL_REFERENCE.md`](TECHNICAL_REFERENCE.md) for the full list of metrics and generated plots.

------------------------------------------------------------------------

## File Structure

```
Ebbinghaus/
├── config/defaults.R               # Configurable parameters (shapes, sizes, colors, etc.)
├── R/
│   ├── generate_design.R           # Phase 1 — Build a complete design matrix
│   ├── render_stimuli.R            # Phase 1 — Batch render trial table to images
│   ├── evaluate.R                  # Phase 2 — vitals-based evaluation pipeline
│   └── analyze.R                   # Phase 3 — Metrics and plots
├── data/
│   ├── trials.csv                  # Trial metadata (Phase 1 output → Phase 2 input)
│   ├── prompts.csv                 # Prompt variants for evaluation (Phase 2 input)
│   └── evals.csv                   # Evaluation results (Phase 2 output → Phase 3 input)
├── images/                         # Rendered stimulus images (Phase 1 output)
├── docs/                           # Reference manuals
├── py/                             # Python implementation (see py/README.md)
└── output/                         # Saved plots (Phase 3, when show_plots = FALSE)
```

`data/` serves as the interchange directory between phases: each phase writes its output there, and the next phase reads from it. For the complete project tree with all internal modules, see [`TECHNICAL_REFERENCE.md`](TECHNICAL_REFERENCE.md).

---

## Reference Manual

For the full internal-function reference, see [`docs/reference_manual.pdf`](docs/reference_manual.pdf).

---

## License & Citation

This project is licensed under [CC BY 4.0](LICENSE.md) - you are free to use, modify, and redistribute with attribution. See [`CITATION.cff`](CITATION.cff) or use the "Cite this repository" button on GitHub.

Visit my [website](https://iamyannc.github.io/Yann-dev) for contact information.
