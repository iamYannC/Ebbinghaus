# Ebbinghaus Benchmark — Shiny App

A Shiny (bslib) interface for **Phase 1** of the Ebbinghaus Benchmark: trial design generation and stimulus rendering.

## What it does

- **Trials** — Configure tiers, seed, and trials per tier, then generate a design matrix. Preview and download as CSV.
- **Stimuli** — Render stimulus images from the design with live progress. Browse in a responsive grid and download as ZIP.
- **Configuration** — Fine-tune all generation parameters (shapes, sizes, colors, canvas, etc.) without editing code.

## Run locally

From the project root:

```r
shiny::runApp("R/App")
```

Requires: `shiny`, `bslib`, `reactable`, `dplyr`, `ggplot2`, `ggforce`.

## Live version

[ebbinghaus-bench](https://tinyurl.com/ebbinghaus-bench)
