# Variable Registry — Python

Python-specific variable reference for the Ebbinghaus Benchmark. For tier definitions, project overview, and the shared trial/prompt schemas, see the [root README](../README.md) and [root Variable Registry](../VARIABLE_REGISTRY.md).

This document covers Python-specific function signatures, types, and Inspect AI concepts.

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

---

**For the complete trial schema, prompt schema, and derived analysis variables, see the [root Variable Registry](../VARIABLE_REGISTRY.md).**
