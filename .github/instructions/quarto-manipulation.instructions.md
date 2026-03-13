---
description: "Use when handling files from the manipulation/ folder for website inclusion. Describes the Ferry/Ellis/Mint/Train/Forecast pipeline structure, file purposes, and how to present pipeline content in the website."
applyTo: "manipulation/**"
---

# Quarto Manipulation Instructions

## manipulation/ Folder Structure

```
manipulation/
├─ 1-ferry.R           — Ferry lane; loads data from 4 sources, writes staging SQLite
├─ 2-ellis.R           — Ellis lane; transforms to 11 analysis-ready tables (Parquet + SQLite)
├─ 3-mint-IS.R         — Mint lane; model-ready slices + forge_manifest.yml
├─ 4-train-IS.R        — Train lane; fits Naive + ARIMA models, saves .rds + model_registry.csv
├─ 5-forecast-IS.R     — Forecast lane; 24-month forecasts, forecast_manifest.yml
├─ pipeline.md         — authoritative technical guide (lane architecture, I/O contracts)
├─ README.md           — philosophy guide (Ferry/Ellis/Mint pattern, naming conventions)
├─ example/
│  ├─ ferry-lane-example.R   — educational Ferry demo
│  └─ ellis-lane-example.R   — educational Ellis demo
├─ images/
│  ├─ flow-skeleton.png
│  ├─ flow-skeleton-01.png
│  ├─ flow-skeleton-02.png
│  └─ flow-skeleton-car.png  — pipeline/pattern diagrams (use in website)
└─ nonflow/
   ├─ create-data-assets.R   — one-time setup (do not include in website)
   ├─ inspect-forge.R        — ad-hoc debug tool (do not include in website)
   └─ test-ellis-cache.R     — quality gate test (do not include in website)
```

## Pipeline Summary

```
Ferry (load) → Ellis (clean/transform) → Mint (model prep) → Train (fit) → Forecast (predict)
                         ↓ advisory
                        EDA-2
```

## Rules for Website Inclusion

### Primary Content Sources

When a `###` section references `manipulation/`:
- **`pipeline.md`** is the primary page content — it is the authoritative technical description.
- If `configuration.prompt.md` says to augment with `./README.md`, merge the pipeline philosophy from `README.md` into the page as a preamble or sidebar section.
- Do not render raw source path tokens (for example `./README.md` or `./philosophy/FIDES-example.md`) as visible page text; use meaningful titles/headings instead.

### Images / Diagrams

- **Use** images from `manipulation/images/` for pipeline visual explanations.
- Preferred order: `flow-skeleton.png` → `flow-skeleton-01.png` → `flow-skeleton-02.png`.
- Copy images into `frontend-*/<section>/images/` and update relative paths.

### Files to Always Exclude from Website

- All `*.R` script files (they are computation code, not documentation)
- `nonflow/` directory and all its contents
- `data-private/` references (sensitive data paths — never expose)

### Data References

The `.R` scripts write outputs to `./data-private/derived/` — this path is sensitive. When summarising lane outputs for website content, describe outputs by type only (e.g., "Parquet files", "SQLite database") without exposing absolute paths.

## Visual Pipeline Summary (for website use)

```
SETUP (run once):
  create-data-assets.R → SQLite + SQL Server sources

FLOW (reproducible):
  1. Ferry   → open-data-is-1.sqlite
  2. Ellis   → open-data-is-2-tables/*.parquet + .sqlite
  3. Mint    → forge/*.parquet + forge_manifest.yml
  4. Train   → models/*.rds + model_registry.csv
  5. Forecast → forecast/*.csv + forecast_manifest.yml
  6. Report  → analysis/report-1/report-1.html
```
