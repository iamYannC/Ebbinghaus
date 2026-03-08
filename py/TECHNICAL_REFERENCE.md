# Technical Reference — Python

Python-specific technical reference for the Ebbinghaus Benchmark. For tier definitions, project overview, and the shared trial/prompt schemas, see the [root README](../README.md) and [root Technical Reference](../TECHNICAL_REFERENCE.md).

This document covers Python-specific function signatures, types, and Inspect AI concepts.

---

## Module Structure

```
py/
├── config/
│   └── defaults.py                 # Configurable parameters (mirrors R defaults)
├── src/
│   ├── generate_design.py          # Phase 1 — Build a complete design matrix
│   ├── generate_trial.py           # Generate a single trial's parameters
│   ├── render_stimuli.py           # Phase 1 — Batch render trial table to images
│   ├── draw_trial.py               # Compose full stimulus image (matplotlib)
│   ├── draw_shape.py               # Atomic shape drawing (matplotlib patches)
│   ├── verify_trial.py             # Compute ground truth from size parameters
│   ├── classify_tier.py            # Assign difficulty tier (0–3)
│   ├── strip_answer.py             # Strip ground truth from filenames for evaluation
│   ├── evaluate.py                 # Phase 2 — Inspect AI evaluation pipeline
│   └── analyze.py                  # Phase 3 — Metrics and plots
├── pyproject.toml                  # Dependencies (uv / pip)
├── README.md
└── TECHNICAL_REFERENCE.md          # This file
```

Shared directories (`data/`, `images/`, `output/`) live at the project root and are used by both R and Python. See the [root Technical Reference](../TECHNICAL_REFERENCE.md) for the full project tree.

---

## Configuration — `config/defaults.py`

Edit [`py/config/defaults.py`](config/defaults.py) to control what `generate_design()` and `generate_trial()` produce. All parameters mirror the R version. Each variable is documented with inline comments.

---

## Model Configuration — `run_evals()`

Passed as a list of dicts to `run_evals()`. Each dict must have:

| Field | Type | Required | Values/Range | Meaning |
|-------|------|----------|--------------|---------|
| `provider` | str | **Yes** | `"anthropic"`, `"openai"`, `"google"` | API provider |
| `model` | str | **Yes** | Provider-specific model ID (e.g., `"gpt-5.4-pro"`) | Model to use |
| `temperature` | float | No (default `0`) | `[0, 2]` | Sampling temperature |
| `max_tokens` | int | No (default `512`) | `> 0` | Max tokens in response |

```python
models = [
    {"provider": "openai", "model": "gpt-5.4-pro"},
    {"provider": "anthropic", "model": "claude-sonnet-4-6", "temperature": 0},
    {"provider": "google", "model": "gemini-3.1-pro-preview"},
]
logs = run_evals(trials, prompts, models)
```

---

## Inspect AI Concepts

| R (vitals) | Python (Inspect AI) | Notes |
|------------|---------------------|-------|
| `Task$new()` | `Task()` | Task definition |
| `ebbinghaus_solver()` | `@solver` decorated function | Passes image + text to model |
| `ebbinghaus_scorer()` | `@scorer` decorated function | Deterministic parse + compare |
| `make_chat()` | `get_model()` | Model instantiation |
| `run_evals()` | `run_evals()` → `inspect_eval()` | Returns list of eval logs |
| `extract_results()` | Parsed from `log.samples` | Flat DataFrame extraction |
| `vitals_view()` | `inspect view` CLI | Opens log viewer |

---

## Dependencies

| Package | Phase | Purpose |
|---------|-------|---------|
| `matplotlib` | 1, 3 | Stimulus rendering and analysis plots |
| `numpy` | 1 | Numeric operations, random sampling |
| `pandas` | 1, 2, 3 | Data manipulation |
| `inspect-ai` | 2 | Evaluation framework (Task, solver, scorer) |
| `seaborn` | 3 | Heatmaps in analysis plots |
| `scipy` | 3 | `norm.ppf()` for d-prime computation |
| `Pillow` | 1 | WebP image format support |

**Phase 1** requires only `matplotlib`, `numpy`, and `pandas`.

**Phase 2** adds `inspect-ai`. If this is too heavy, adapt the legacy CSV workflow from `R/legacy/evaluate.R`.

**Phase 3** adds `seaborn` and `scipy`.

---

## Key Differences from R Version

| Aspect | R | Python |
|--------|---|--------|
| Data frames | `data.frame` | `pandas.DataFrame` |
| Config format | `config/defaults.R` (R script) | `config/defaults.py` (Python module) |
| Rendering | `ggplot2` + `ggforce` | `matplotlib` patches |
| Evaluation framework | `vitals` + `ellmer` | `inspect-ai` |
| Analysis | `dplyr` + `tidyr` + `ggplot2` | `pandas` + `matplotlib` + `seaborn` |
| PRNG | R's Mersenne-Twister | NumPy's `RandomState` |
| `created_with` column | `"r"` | `"py"` |

Same seeds will **not** produce identical trial tables across R and Python due to different PRNG implementations. Reproducibility is within-language only.

`master_seed` is always populated — if no seed was passed to `generate_design()`, the auto-generated seed is stored. Reproduce via: `generate_design(seed=int(trials["master_seed"].iloc[0]))`.

---

**For the complete trial schema, prompt schema, and derived analysis variables, see the [root Technical Reference](../TECHNICAL_REFERENCE.md).**
