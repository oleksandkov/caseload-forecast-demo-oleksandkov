# Forecast Lane 5: Implementation and Artifact Contract

**Date**: 2026-02-23  
**Scope**: `manipulation/5-forecast-IS.R`, `config.yml`, `flow.R`, `manipulation/pipeline.md`  
**Trigger**: Human request to implement Lane 5 (Forecast) for Tiers 1–2, anticipating
  Report lane (Lane 6) consumption needs

---

## Summary

Implemented `manipulation/5-forecast-IS.R` — the prediction generation lane that loads
Train lane `.rds` model objects, generates 24-month forward projections with 80%/95%
prediction intervals, produces in-sample backtest diagnostic data, and persists five
structured artifacts for the Report lane. Script completes in ~3 seconds.

---

## Forecast Window

| Parameter | Value |
|-----------|-------|
| `focal_date` | 2025-09-01 (last observed month) |
| First forecast month | 2025-10-01 |
| Last forecast month | 2027-09-01 |
| Horizon | 24 months |
| Back-transform | `exp()` applied to all forecast outputs (log scale → original caseload scale) [EDA-001] |

---

## Architecture Decisions

### Forbidden: No Model Refitting

The Forecast lane **never** calls `snaive()`, `auto.arima()`, or any model estimation
function. All `.rds` objects are loaded and consumed via `forecast(readRDS(rds_path), h = 24)`.
The Train lane is responsible for fitting on `ts_full`; the Forecast lane is responsible
only for projecting forward from what the models already know.

### Mandatory: forge_hash Lineage Validation

Before loading any model, Section 3 compares `forge_hash` from `model_registry.csv`
against the current `forge_manifest.yml`. If they differ, the script stops:

```
Lineage mismatch: forge_hash in model_registry.csv ('old_hash') does not match
current forge_manifest.yml ('new_hash'). Re-run 3-mint-IS.R and 4-train-IS.R
before forecasting.
```

This prevents silently forecasting from stale models when `focal_date` is updated.

### Backtest Comparison vs True Hold-out Metrics

Two distinct items in the forecast output directory serve different purposes:

| Item | Source | Purpose |
|------|--------|---------|
| `backtest_comparison.csv` | `fitted()` on full-series `.rds` models | **Visual diagnostics**: actual-vs-fitted lines, residual patterns |
| `model_performance.csv` | Copied from `model_registry.csv` | **Accuracy numbers**: RMSE/MAE/MAPE computed in Lane 4 on the true 24-month hold-out |

The `backtest_comparison.csv` contains **in-sample fitted values** (one-step-ahead
predictions from models trained on all 246 months), not true out-of-sample forecasts.
Do **not** use these for model selection or accuracy comparison — use
`model_performance.csv` for that. The fitted values exist solely so the Report lane
can draw an actual-vs-predicted overlay for the test window without consuming the
Train lane's intermediate backtest arrays.

### CSV, Not Parquet, for Forecast Artifacts

Forecast output is small (~15 KB total, 48–24 rows). CSV was chosen over Parquet
because: (a) human-readable for debugging, (b) Report lane (Quarto) uses
`read.csv()` directly, (c) no columnar compression benefit at this scale.

### Dual Format (Long + Wide)

`forecast_long.csv` is the primary consumption format (ggplot2 faceting). The
`forecast_wide.csv` pivot is a convenience for kable comparison tables in the Report
lane; it is derived from long and adds no new information.

---

## Artifacts Produced

All artifacts written to `./data-private/derived/forecast/` (~14.5 KB total).

### `forecast_long.csv` (48 rows = 2 models × 24 months)

**Primary Report lane artifact.** One row per model × forecast month.

| Column | Type | Description |
|--------|------|-------------|
| `date` | chr (Date) | First of month, "YYYY-MM-DD" format |
| `year` | int | Calendar year |
| `month` | int | Month number (1–12) |
| `fiscal_year` | chr | Alberta FY label, e.g. `"FY 2025-26"` |
| `month_label` | chr | Human-readable, e.g. `"Oct 2025"` |
| `model_id` | chr | `"tier_1_snaive"` \| `"tier_2_arima"` |
| `tier` | int | `1` \| `2` |
| `tier_label` | chr | `"Naive Baseline"` \| `"ARIMA"` |
| `point_forecast` | num | Point forecast, original caseload scale |
| `lo_80` / `hi_80` | num | 80% prediction interval bounds |
| `lo_95` / `hi_95` | num | 95% prediction interval bounds |

**Forecast value ranges** (Oct 2025 – Sep 2027):

| Tier | Point forecast range | Notes |
|------|---------------------|-------|
| Tier 1 — snaive | 57,455 – 61,708 | Repeating 2024-25 seasonal pattern |
| Tier 2 — ARIMA `(3,1,1)(1,0,0)[12]` | 61,073 – 61,794 | Near-flat trend, seasonal modulation |

---

### `forecast_wide.csv` (24 rows = 24 forecast months)

One row per forecast month; one column group per model.
Column naming: `{metric}__{model_id}` (double underscore separator).

Example columns:
```
date, year, month, fiscal_year, month_label,
point_forecast__tier_1_snaive, point_forecast__tier_2_arima,
lo_80__tier_1_snaive, lo_80__tier_2_arima,
hi_80__tier_1_snaive, hi_80__tier_2_arima,
lo_95__tier_1_snaive, lo_95__tier_2_arima,
hi_95__tier_1_snaive, hi_95__tier_2_arima
```

---

### `backtest_comparison.csv` (48 rows = 2 models × 24 test months)

In-sample fitted values for the test window (Oct 2023 – Sep 2025), for visual
diagnostic plots. **Not** for accuracy comparison — see `model_performance.csv`.

| Column | Type | Description |
|--------|------|-------------|
| `date` | chr (Date) | Test window month |
| `actual_caseload` | num | Observed caseload |
| `model_id` | chr | Model identifier |
| `tier` | int | Tier number |
| `tier_label` | chr | Human-readable label |
| `fitted_caseload` | num | In-sample fitted value (exp back-transformed) |
| `residual` | num | `actual_caseload - fitted_caseload` |
| `pct_error` | num | `(residual / actual) × 100` |

---

### `model_performance.csv` (2 rows)

True hold-out backtest metrics from Lane 4. Subset of `model_registry.csv`
selected for Report lane display. Key columns:

| Column | Description |
|--------|-------------|
| `model_id` | Model identifier |
| `tier` / `tier_label` | Tier number and label |
| `model_description` | Full model description string |
| `arima_order` | ARIMA order string; NA for snaive |
| `aic` / `aicc` / `bic` | Information criteria; NA for snaive |
| `backtest_rmse` | RMSE on 24-month hold-out (original scale) |
| `backtest_mae` | MAE on 24-month hold-out |
| `backtest_mape` | MAPE percentage on 24-month hold-out |
| `n_train` / `n_test` / `n_full` | Data slice sizes |
| `focal_date` | `"2025-09-01"` |
| `forge_hash` | Lineage bond |
| `trained_at` | Train execution timestamp |

**Current values**:

| Model | RMSE | MAE | MAPE |
|-------|------|-----|------|
| Tier 1 — Naive Baseline | 10,300 | 9,545 | 16.4% |
| Tier 2 — ARIMA `(3,1,1)(1,0,0)[12]` | 8,639 | 7,831 | 13.3% |

---

### `forecast_manifest.yml`

YAML linking Forecast artifacts to the Mint-Train lineage chain.

```yaml
forecast_hash: fa43528f49351759fe7b2742c44444ef   # md5 of all 4 CSVs combined
forge_hash_consumed: 3ef1c81a04b78581f3df84e0a68f1504
mint_train_forecast_chain: "versioned by focal_date; changing focal_date invalidates all Mint/Train/Forecast artifacts"

forecast_parameters:
  focal_date: "2025-09-01"
  first_forecast_month: "2025-10-01"
  last_forecast_month: "2027-09-01"
  forecast_horizon_months: 24
  random_seed: 42
  transform: "log (EDA-001); back-transformed via exp()"

models_forecasted:
  - model_id: tier_1_snaive
    tier: 1
    tier_label: Naive Baseline
    backtest_rmse: 10300.2
    backtest_mape: 16.36
  - model_id: tier_2_arima
    tier: 2
    tier_label: ARIMA
    backtest_rmse: 8638.6
    backtest_mape: 13.349

artifacts:
  forecast_long:    {file: forecast_long.csv,        n_rows: 48}
  forecast_wide:    {file: forecast_wide.csv,        n_rows: 24,  n_cols: 15}
  backtest:         {file: backtest_comparison.csv,  n_rows: 48}
  performance:      {file: model_performance.csv,    n_rows: 2}
  manifest:         {file: forecast_manifest.yml}

report_lane_notes:
  recommended_plots:
    - ggplot ribbon: date vs point_forecast + lo_95/hi_95 from forecast_long.csv
    - ggplot facet_wrap: by tier_label for tier comparison
    - actual-vs-fitted: backtest_comparison.csv
    - kable table: model_performance.csv RMSE/MAE/MAPE
```

---

## Script Structure (`manipulation/5-forecast-IS.R`)

Ten sections following the lane conventions established across lanes 3 and 4:

| Section | Content |
|---------|---------|
| Header | Roxygen-style docs: purpose, input, output, forbidden, EDA traceability, Lane 6 hand-off notes |
| Setup | `rm`, `cat("\014")`, `script_start`, load packages, source scripts |
| §1 Load Inputs | `forge_manifest.yml`, `model_registry.csv`, `ds_full.parquet` |
| §2 Reconstruct ts_full | From `ds_full$y`; back-transform spot-check |
| §3 Validate forge_hash | Lineage guard; `checkmate` assertions; fails hard on mismatch |
| §4 Generate Forward Forecasts | Loop over registry; `readRDS` → `forecast(h=24)` → `exp()` back-transform; assemble `ds_forecast_long` |
| §5 Build Backtest Comparison | `fitted()` on full-series models; filter to test window; join actuals; compute residuals |
| §6 Build Wide Table | `tidyr::pivot_wider()` on `ds_forecast_long` |
| §7 Model Performance Table | Subset of `model_registry` columns for Report display |
| §8 Write Artifacts | `write.csv()` × 4; round-trip verification |
| §9 Forecast Manifest | `digest::digest()` hash of all CSVs; `yaml::write_yaml()` |
| §10 Session Info | Duration, artifact sizes, lineage chain summary, Lane 6 instructions |

---

## Report Lane (6-report-IS.qmd): Recommended Loading Pattern

```r
# In 6-report-IS.qmd setup chunk:
library(config)
library(dplyr)
library(ggplot2)
library(yaml)

config       <- config::get()
dir_fc       <- config$directories$forecast

forecast_long <- read.csv(file.path(dir_fc, "forecast_long.csv")) %>%
  mutate(date = as.Date(date))

forecast_wide <- read.csv(file.path(dir_fc, "forecast_wide.csv")) %>%
  mutate(date = as.Date(date))

backtest      <- read.csv(file.path(dir_fc, "backtest_comparison.csv")) %>%
  mutate(date = as.Date(date))

performance   <- read.csv(file.path(dir_fc, "model_performance.csv"))
fc_manifest   <- yaml::read_yaml(file.path(dir_fc, "forecast_manifest.yml"))
```

### Ribbon Forecast Plot (standard recipe)

```r
# Load observed data for historical context
dir_forge <- config$directories$forge
ds_full   <- arrow::read_parquet(file.path(dir_forge, "ds_full.parquet")) %>%
  mutate(date = as.Date(date))

# Standard palette for tier comparison
tier_colors <- c("Naive Baseline" = "#4A90D9", "ARIMA" = "#E87722")

ggplot() +
  # Historical observed line
  geom_line(data = ds_full, aes(x = date, y = caseload),
            colour = "grey40", linewidth = 0.5) +
  # 95% ribbon per tier
  geom_ribbon(data = forecast_long,
              aes(x = date, ymin = lo_95, ymax = hi_95, fill = tier_label),
              alpha = 0.12) +
  # 80% ribbon per tier
  geom_ribbon(data = forecast_long,
              aes(x = date, ymin = lo_80, ymax = hi_80, fill = tier_label),
              alpha = 0.20) +
  # Point forecast lines
  geom_line(data = forecast_long,
            aes(x = date, y = point_forecast, colour = tier_label),
            linewidth = 0.9) +
  scale_colour_manual(values = tier_colors) +
  scale_fill_manual(values = tier_colors) +
  scale_y_continuous(labels = scales::comma) +
  labs(title    = "Alberta Income Support: 24-Month Horizon Forecast",
       subtitle = paste0("Forecast period: ",
                         fc_manifest$forecast_parameters$first_forecast_month,
                         " – ",
                         fc_manifest$forecast_parameters$last_forecast_month),
       x = NULL, y = "Active Caseload", colour = "Model", fill = "Model") +
  theme_bw()
```

### Model Performance Table

```r
library(knitr)
library(kableExtra)

performance %>%
  select(tier, tier_label, arima_order, backtest_rmse, backtest_mae, backtest_mape) %>%
  rename(Tier             = tier,
         Model            = tier_label,
         `ARIMA Order`    = arima_order,
         RMSE             = backtest_rmse,
         MAE              = backtest_mae,
         `MAPE (%)`       = backtest_mape) %>%
  kable(format = "html", digits = 1,
        caption = "Model Backtest Accuracy: 24-Month Hold-Out (Oct 2023 – Sep 2025)") %>%
  kable_styling(bootstrap_options = c("striped", "hover"), full_width = FALSE)
```

### Backtest Actual vs Fitted Plot

```r
ggplot(backtest, aes(x = date)) +
  geom_line(aes(y = actual_caseload),  colour = "grey30", linewidth = 0.5) +
  geom_line(aes(y = fitted_caseload, colour = tier_label), linewidth = 0.8) +
  facet_wrap(~tier_label, ncol = 1) +
  scale_colour_manual(values = tier_colors) +
  scale_y_continuous(labels = scales::comma) +
  labs(title    = "In-Sample Fitted vs Actual: Test Window Diagnostics",
       subtitle = "NOTE: In-sample fitted values only; true hold-out metrics in model_performance.csv",
       x = NULL, y = "Active Caseload", colour = "Model") +
  theme_bw()
```

---

## Mint-Train-Forecast Lineage State

```
forge_hash    : 3ef1c81a04b78581f3df84e0a68f1504   (produced by 3-mint-IS.R)
  → train used this hash (stamped in model_registry.csv)
  → forecast validated this hash (Section 3 lineage guard)
forecast_hash : fa43528f49351759fe7b2742c44444ef   (produced by this run)

focal_date    : 2025-09-01
train         : 222 months (Apr 2005 – Sep 2023)
test          : 24 months  (Oct 2023 – Sep 2025)
full          : 246 months (Apr 2005 – Sep 2025)
forecast      : 24 months  (Oct 2025 – Sep 2027)
```

Changing `focal_date` in `config.yml` invalidates all Mint, Train, and Forecast
artifacts. Re-run lanes 3 → 4 → 5 in sequence to regenerate with the new focal date.

---

## Files Modified

| File | Change |
|------|--------|
| `manipulation/5-forecast-IS.R` | **Created** — ~280 lines, 10 sections |
| `config.yml` | Added `directories.forecast: "./data-private/derived/forecast/"` |
| `flow.R` | Uncommented `"run_r", "manipulation/5-forecast-IS.R"` in Phase 5 of `ds_rail` |
| `manipulation/pipeline.md` | Added `5-forecast-IS.R` documentation section; updated Maintenance Notes |

## Artifacts Produced

| File | Size | Rows | Description |
|------|------|------|-------------|
| `data-private/derived/forecast/forecast_long.csv` | 5.3 KB | 48 | Long format forecasts + intervals |
| `data-private/derived/forecast/forecast_wide.csv` | 3.1 KB | 24 | Wide format side-by-side comparison |
| `data-private/derived/forecast/backtest_comparison.csv` | 3.2 KB | 48 | In-sample fitted vs actual, test window |
| `data-private/derived/forecast/model_performance.csv` | 0.7 KB | 2 | RMSE/MAE/MAPE from Train hold-out |
| `data-private/derived/forecast/forecast_manifest.yml` | 2.2 KB | — | Lineage YAML, artifact inventory |

---

## Problems Encountered

None. Script ran cleanly in ~3 seconds. No model refitting involved (pure
`readRDS` → `forecast` → `fitted` operations), so execution is near-instant
compared to the ~64 seconds of Lane 4's `auto.arima()` calls.

---

## What's Next

- Implement `analysis/forecast-1/forecast-1.qmd` — Quarto report (Report lane, Lane 6)
  - Load all 5 artifacts from `data-private/derived/forecast/` via `config$directories$forecast`
  - Load `ds_full.parquet` from forge for historical context ribbon (pre-forecast observation window)
  - Plot 1: Ribbon forecast (historical + 24-month horizon, both tiers, 80% + 95% bands)
  - Plot 2: Tier comparison panel (`facet_wrap(~tier_label)`)
  - Plot 3: Actual-vs-fitted backtest diagnostic (using `backtest_comparison.csv`)
  - Table 1: Model performance (`model_performance.csv`, RMSE/MAE/MAPE)
  - Table 2: Forecast values (`forecast_wide.csv`, side-by-side point forecasts)
  - Metadata block: Pull `focal_date`, `forecast_hash`, `forge_hash` from `forecast_manifest.yml`
  - Render to static HTML; activate in `flow.R` Phase 6
