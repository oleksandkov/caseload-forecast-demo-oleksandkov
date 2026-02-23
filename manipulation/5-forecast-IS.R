#' ---
#' title: "Forecast Lane 5: Income Support 24-Month Horizon Predictions"
#' author: "GoA Analytics Team"
#' date: "2026-02-23"
#' ---
#'
#' ============================================================================
#' FORECAST PATTERN: Generate Forward Projections from Train Model Objects
#' ============================================================================
#'
#' **Purpose**: Consume fitted model objects from the Train lane and produce
#'   structured forecast artifacts for downstream Report lane consumption.
#'   Generates 24-month forward projections (Oct 2025 – Sep 2027) with
#'   80% and 95% prediction intervals, in-sample backtest diagnostics,
#'   and a forecast manifest documenting lineage to Mint artifacts.
#'
#' **Input**:
#'   - ./data-private/derived/models/model_registry.csv  : Model metadata, metrics, paths
#'   - ./data-private/derived/models/tier_1_snaive.rds  : Seasonal naive (fitted on ts_full)
#'   - ./data-private/derived/models/tier_2_arima.rds   : ARIMA (fitted on ts_full)
#'   - ./data-private/derived/forge/ds_full.parquet     : Full data series (246 months)
#'   - ./data-private/derived/forge/forge_manifest.yml  : Forge contract (forge_hash, dates)
#'   - config.yml                                        : focal_date, forecast_horizon, paths
#'
#' **Output** (all saved to ./data-private/derived/forecast/):
#'   - forecast_long.csv         : Long format: one row per model × forecast month
#'                                  Columns: date, year, month, fiscal_year, month_label,
#'                                           model_id, tier, tier_label,
#'                                           point_forecast, lo_80, hi_80, lo_95, hi_95
#'   - forecast_wide.csv         : Wide format: one row per forecast month, models as columns
#'                                  Optimised for side-by-side comparison tables in Report
#'   - backtest_comparison.csv   : In-sample fitted vs actual for test window (24 months)
#'                                  Columns: date, actual_caseload, model_id, tier, tier_label,
#'                                           fitted_caseload, residual
#'                                  NOTE: fitted values are one-step in-sample predictions
#'                                  from the full-series models, NOT true hold-out forecasts.
#'                                  True backtest metrics (RMSE/MAE/MAPE) are in
#'                                  model_performance.csv (computed in 4-train-IS.R).
#'   - model_performance.csv     : Backtest performance metrics for all tiers
#'                                  (subset of model_registry columns, Report-ready)
#'   - forecast_manifest.yml     : Lineage YAML: forecast_hash, forge_hash consumed,
#'                                  focal_date, artifact inventory, execution timestamp
#'
#' **Forbidden**: Refitting models (auto.arima / snaive on any data slice),
#'   reading Ellis output directly, producing new data transformations
#'
#' **Model Tiers Forecasted**:
#'   Tier 1 (snaive):    Seasonal naive — readRDS -> forecast(h=24)
#'   Tier 2 (ARIMA):     Auto ARIMA    — readRDS -> forecast(h=24)
#'
#' **EDA Decision Traceability** (codified in 3-mint-IS.R):
#'   [EDA-001] Log transform: TRUE — back-transform via exp() for all forecasts
#'   [EDA-003] Seasonal period: 12 — models already account for seasonality
#'   [EDA-004] 24-month backtest window — test window is Oct 2023 – Sep 2025
#'
#' **Report Lane Hand-off (6-report-IS.qmd)**:
#'   - Load forecast_long.csv  -> ggplot2 ribbon + line forecast plots (facet by tier)
#'   - Load forecast_wide.csv  -> kable comparison table (all models side-by-side)
#'   - Load backtest_comparison.csv -> actual-vs-fitted residual diagnostic plots
#'   - Load model_performance.csv  -> performance metrics table (RMSE, MAE, MAPE)
#'   - Load forecast_manifest.yml  -> provenance metadata for report header
#'
#' ============================================================================

#+ echo=F
# rmarkdown::render(input = "./manipulation/5-forecast-IS.R") # run to knit

# ---- setup -------------------------------------------------------------------
rm(list = ls(all.names = TRUE))
cat("\014")

script_start <- Sys.time()

# ---- load-packages -----------------------------------------------------------
library(magrittr)
library(dplyr)
library(tidyr)
library(lubridate)
library(forecast)   # forecast(), fitted()
requireNamespace("arrow")
requireNamespace("checkmate")
requireNamespace("yaml")
requireNamespace("digest")
requireNamespace("config")

# ---- load-sources ------------------------------------------------------------
base::source("./scripts/common-functions.R")
base::source("./scripts/operational-functions.R")

# ---- declare-globals ---------------------------------------------------------
config <- config::get()

dir_forge    <- config$directories$forge
dir_models   <- config$directories$models
dir_forecast <- config$directories$forecast

focal_date       <- as.Date(config$focal_date)
forecast_horizon <- config$forecast_horizon
random_seed      <- config$random_seed

# Helper: back-transform log-scale values to original caseload scale
# [EDA-001] Mint applied y = log(caseload); reverse with exp()
back_transform <- function(y_hat) {
  exp(y_hat)
}

# Helper: generate Alberta fiscal year label from a Date vector
# Delegates to operational-functions.R if available; otherwise inlines
make_fiscal_year <- function(d) {
  # Alberta FY: April 1 – March 31.  Apr 2025 is "FY 2025-26".
  yr  <- year(d)
  mo  <- month(d)
  fy_start <- ifelse(mo >= 4, yr, yr - 1L)
  fy_end   <- (fy_start + 1L) %% 100        # last two digits
  sprintf("FY %d-%02d", fy_start, fy_end)
}

# Helper: human-readable month-year label (e.g. "Oct 2025")
make_month_label <- function(d) {
  format(d, "%b %Y")
}

# Create output directory if it does not yet exist
dir.create(dir_forecast, recursive = TRUE, showWarnings = FALSE)

cat("\n", strrep("=", 70), "\n")
cat("FORECAST LANE 5: Income Support 24-Month Horizon Predictions\n")
cat(strrep("=", 70), "\n")
cat("  focal_date       :", format(focal_date), "\n")
cat("  forecast_horizon :", forecast_horizon, "months\n")
cat("  random_seed      :", random_seed, "\n")
cat("  forge dir        :", dir_forge, "\n")
cat("  models dir       :", dir_models, "\n")
cat("  forecast dir     :", dir_forecast, "\n")
cat("  Executed         :", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")

# ==============================================================================
# SECTION 1: LOAD INPUTS
# ==============================================================================

# ---- load-data ---------------------------------------------------------------
cat("\n", strrep("=", 70), "\n")
cat("SECTION 1: Load Inputs\n")
cat(strrep("=", 70), "\n")

# -- 1a. Forge manifest (lineage source) --
manifest_path <- file.path(dir_forge, "forge_manifest.yml")
checkmate::assert_file_exists(manifest_path, .var.name = "forge_manifest.yml")
forge_manifest <- yaml::read_yaml(manifest_path)
forge_hash     <- forge_manifest$forge_hash

# -- 1b. Model registry (model discovery) --
registry_path <- file.path(dir_models, "model_registry.csv")
checkmate::assert_file_exists(registry_path, .var.name = "model_registry.csv")
model_registry <- read.csv(registry_path, stringsAsFactors = FALSE)

# -- 1c. Full series data (for date reconstruction) --
path_ds_full <- file.path(dir_forge, "ds_full.parquet")
checkmate::assert_file_exists(path_ds_full, .var.name = "ds_full.parquet")
ds_full <- arrow::read_parquet(path_ds_full)

cat("\n  Loaded:\n")
cat("    forge_manifest.yml  : forge_hash =", forge_hash, "\n")
cat("    model_registry.csv  :", nrow(model_registry), "model(s)\n")
cat("    ds_full.parquet     :", nrow(ds_full), "rows |",
    format(min(ds_full$date)), "to", format(max(ds_full$date)), "\n")

# ==============================================================================
# SECTION 2: RECONSTRUCT TIME SERIES OBJECT
# ==============================================================================

# ---- reconstruct-ts ----------------------------------------------------------
cat("\n", strrep("=", 70), "\n")
cat("SECTION 2: Reconstruct ts_full from ds_full.parquet\n")
cat(strrep("=", 70), "\n")

ts_start_from <- function(df) {
  c(year(min(df$date)), month(min(df$date)))
}

ts_full <- ts(ds_full$y, start = ts_start_from(ds_full), frequency = 12)

cat("\n  ts_full: length =", length(ts_full),
    "| start =", paste(start(ts_full), collapse = ","),
    "| end =",   paste(end(ts_full),   collapse = ","), "\n")
cat("  Back-transform check: exp(ts_full[1]) =",
    round(exp(ts_full[1]), 0), "(expected ~27,969)\n")

# ==============================================================================
# SECTION 3: VALIDATE DATA CONTRACT (Lineage Check)
# ==============================================================================

# ---- validate-data -----------------------------------------------------------
cat("\n", strrep("=", 70), "\n")
cat("SECTION 3: Validate forge_hash Lineage\n")
cat(strrep("=", 70), "\n")

# Confirm all registry models reference the same forge_hash as current manifest.
# If hashes diverge, Mint was re-run after Training — artifacts are misaligned.
registry_hashes <- unique(model_registry$forge_hash)
if (length(registry_hashes) != 1) {
  stop(
    "model_registry.csv contains multiple forge_hash values. ",
    "Inconsistent Train lane artifacts detected: ",
    paste(registry_hashes, collapse = ", ")
  )
}
if (registry_hashes != forge_hash) {
  stop(
    "Lineage mismatch: forge_hash in model_registry.csv ('", registry_hashes,
    "') does not match current forge_manifest.yml ('", forge_hash, "'). ",
    "Re-run 3-mint-IS.R and 4-train-IS.R before forecasting."
  )
}

# Confirm ts_full length matches manifest
checkmate::assert_true(
  length(ts_full) == forge_manifest$data_slices$full$n_months,
  .var.name = "ts_full length vs forge_manifest$data_slices$full$n_months"
)

# Confirm log transform is active [EDA-001]
checkmate::assert_true(
  isTRUE(forge_manifest$transform_decisions$log_transform),
  .var.name = "forge_manifest log_transform flag"
)

# Confirm model .rds files exist for all registry rows
for (i in seq_len(nrow(model_registry))) {
  checkmate::assert_file_exists(
    model_registry$rds_path[i],
    .var.name = paste0(model_registry$model_id[i], " .rds path")
  )
}

cat("\n  forge_hash matches between registry and manifest:", forge_hash, "\n")
cat("  ts_full length confirmed:", length(ts_full), "months\n")
cat("  Log transform flag confirmed: TRUE [EDA-001]\n")
cat("  All .rds files present:", nrow(model_registry), "model(s)\n")
cat("  All assertions passed.\n")

# ==============================================================================
# SECTION 4: GENERATE 24-MONTH FORWARD FORECASTS
# ==============================================================================

# ---- generate-forecasts ------------------------------------------------------
cat("\n", strrep("=", 70), "\n")
cat("SECTION 4: Generate 24-Month Forward Forecasts\n")
cat(strrep("=", 70), "\n")

# Build the vector of future forecast dates (Oct 2025 – Sep 2027)
# first_forecast_date is one month after the last observed month (focal_date)
first_forecast_date <- focal_date %m+% months(1L)
forecast_dates <- seq.Date(first_forecast_date,
                            by    = "month",
                            length.out = forecast_horizon)

cat("\n  Forecast window:", format(first_forecast_date), "to",
    format(max(forecast_dates)), "(", forecast_horizon, "months)\n")

set.seed(random_seed)

# Accumulate long-format rows across all model tiers
forecast_rows <- vector("list", nrow(model_registry))

for (i in seq_len(nrow(model_registry))) {
  row <- model_registry[i, ]

  cat("\n  [Tier", row$tier, "] Loading:", row$model_id, "\n")

  model_obj <- readRDS(row$rds_path)
  fc        <- forecast::forecast(model_obj, h = forecast_horizon)

  # Extract and back-transform from log scale [EDA-001]
  pt   <- back_transform(as.numeric(fc$mean))
  lo80 <- back_transform(as.numeric(fc$lower[, "80%"]))
  hi80 <- back_transform(as.numeric(fc$upper[, "80%"]))
  lo95 <- back_transform(as.numeric(fc$lower[, "95%"]))
  hi95 <- back_transform(as.numeric(fc$upper[, "95%"]))

  cat("    Point forecast range: [",
      round(min(pt), 0), ",", round(max(pt), 0), "] (original caseload scale)\n")

  forecast_rows[[i]] <- data.frame(
    date           = forecast_dates,
    year           = year(forecast_dates),
    month          = month(forecast_dates),
    fiscal_year    = make_fiscal_year(forecast_dates),
    month_label    = make_month_label(forecast_dates),
    model_id       = row$model_id,
    tier           = row$tier,
    tier_label     = row$tier_label,
    point_forecast = round(pt,   1),
    lo_80          = round(lo80, 1),
    hi_80          = round(hi80, 1),
    lo_95          = round(lo95, 1),
    hi_95          = round(hi95, 1),
    stringsAsFactors = FALSE
  )
}

ds_forecast_long <- do.call(rbind, forecast_rows)
rownames(ds_forecast_long) <- NULL

cat("\n  forecast_long assembled:", nrow(ds_forecast_long), "rows",
    "(", nrow(model_registry), "models x", forecast_horizon, "months)\n")
checkmate::assert_true(nrow(ds_forecast_long) == nrow(model_registry) * forecast_horizon)

# ==============================================================================
# SECTION 5: BUILD BACKTEST COMPARISON (In-Sample Fitted vs Actual)
# ==============================================================================

# ---- build-backtest-comparison -----------------------------------------------
cat("\n", strrep("=", 70), "\n")
cat("SECTION 5: Build Backtest Comparison\n")
cat(strrep("=", 70), "\n")

# The .rds models are fitted on ts_full (all 246 months).
# fitted() returns in-sample one-step-ahead predictions for the observed period.
# We filter to the test window (Oct 2023 – Sep 2025) to give the Report lane
# actual-vs-fitted data for diagnostic visualisations.
#
# NOTE: These are in-sample fitted values, NOT the true hold-out backtest
# forecasts computed in 4-train-IS.R. True out-of-sample backtest metrics
# (RMSE, MAE, MAPE) are in model_registry.csv / model_performance.csv.
# For the Report lane, these fitted values provide visual residual diagnostics
# while model_performance.csv supplies the definitive accuracy numbers.

test_start <- as.Date(forge_manifest$data_slices$test$start)
test_end   <- as.Date(forge_manifest$data_slices$test$end)

ds_actuals_test <- ds_full %>%
  dplyr::filter(date >= test_start & date <= test_end) %>%
  dplyr::select(date, actual_caseload = caseload)

cat("\n  Test window for backtest comparison:",
    format(test_start), "to", format(test_end),
    "(", nrow(ds_actuals_test), "months)\n")

set.seed(random_seed)

backtest_rows <- vector("list", nrow(model_registry))

for (i in seq_len(nrow(model_registry))) {
  row <- model_registry[i, ]

  cat("  [Tier", row$tier, "] Extracting fitted values for test window:", row$model_id, "\n")

  model_obj    <- readRDS(row$rds_path)
  fitted_log   <- as.numeric(fitted(model_obj))
  fitted_orig  <- round(back_transform(fitted_log), 1)

  # ds_full has 246 rows; fitted vector has 246 values — align by position
  stopifnot(length(fitted_log) == nrow(ds_full))

  ds_fitted_all <- ds_full %>%
    dplyr::mutate(fitted_caseload = fitted_orig) %>%
    dplyr::filter(date >= test_start & date <= test_end) %>%
    dplyr::select(date, fitted_caseload)

  # Join actuals to fitted values on date
  df_cmp <- dplyr::left_join(ds_actuals_test, ds_fitted_all, by = "date") %>%
    dplyr::mutate(
      model_id        = row$model_id,
      tier            = row$tier,
      tier_label      = row$tier_label,
      residual        = round(actual_caseload - fitted_caseload, 1),
      pct_error       = round((residual / actual_caseload) * 100, 3)
    )

  backtest_rows[[i]] <- df_cmp
}

ds_backtest <- do.call(rbind, backtest_rows) %>%
  dplyr::select(date, actual_caseload, model_id, tier, tier_label,
                fitted_caseload, residual, pct_error)
rownames(ds_backtest) <- NULL

cat("\n  backtest_comparison assembled:", nrow(ds_backtest), "rows",
    "(", nrow(model_registry), "models x", nrow(ds_actuals_test), "months)\n")
checkmate::assert_true(nrow(ds_backtest) == nrow(model_registry) * nrow(ds_actuals_test))

# ==============================================================================
# SECTION 6: BUILD WIDE FORECAST COMPARISON TABLE
# ==============================================================================

# ---- build-forecast-wide -----------------------------------------------------
cat("\n", strrep("=", 70), "\n")
cat("SECTION 6: Build Wide Forecast Comparison Table\n")
cat(strrep("=", 70), "\n")

# One row per forecast month; one column set per model tier.
# Column naming convention: {metric}__{model_id}
# (double underscore separates metric from tier ID for easy parsing in Report)

ds_forecast_wide <- ds_forecast_long %>%
  dplyr::select(date, year, month, fiscal_year, month_label,
                model_id, point_forecast, lo_80, hi_80, lo_95, hi_95) %>%
  tidyr::pivot_wider(
    names_from  = model_id,
    values_from = c(point_forecast, lo_80, hi_80, lo_95, hi_95),
    names_sep   = "__"
  )

cat("\n  forecast_wide assembled:", nrow(ds_forecast_wide), "rows x",
    ncol(ds_forecast_wide), "columns\n")
cat("  Columns (sample):", paste(head(names(ds_forecast_wide), 8), collapse = ", "), "...\n")

# ==============================================================================
# SECTION 7: ASSEMBLE MODEL PERFORMANCE TABLE
# ==============================================================================

# ---- model-performance -------------------------------------------------------
cat("\n", strrep("=", 70), "\n")
cat("SECTION 7: Assemble Model Performance Table\n")
cat(strrep("=", 70), "\n")

# Subset of model_registry columns most useful for Report lane display
model_performance <- model_registry %>%
  dplyr::select(
    model_id, tier, tier_label, model_description,
    arima_order,
    aic, aicc, bic,
    backtest_rmse, backtest_mae, backtest_mape,
    n_train, n_test, n_full,
    focal_date, forge_hash, trained_at
  )

cat("\n  model_performance table:", nrow(model_performance), "rows x",
    ncol(model_performance), "columns\n")
for (i in seq_len(nrow(model_performance))) {
  cat("  [", model_performance$model_id[i], "]\n")
  cat("    tier        :", model_performance$tier[i], "-",
      model_performance$tier_label[i], "\n")
  cat("    RMSE        :", model_performance$backtest_rmse[i],
      "(hold-out 24-month, original scale)\n")
  cat("    MAE         :", model_performance$backtest_mae[i], "\n")
  cat("    MAPE        :", model_performance$backtest_mape[i], "%\n")
}

# ==============================================================================
# SECTION 8: WRITE FORECAST ARTIFACTS
# ==============================================================================

# ---- save-forecasts ----------------------------------------------------------
cat("\n", strrep("=", 70), "\n")
cat("SECTION 8: Write Forecast Artifacts\n")
cat(strrep("=", 70), "\n")

path_forecast_long   <- file.path(dir_forecast, "forecast_long.csv")
path_forecast_wide   <- file.path(dir_forecast, "forecast_wide.csv")
path_backtest        <- file.path(dir_forecast, "backtest_comparison.csv")
path_performance     <- file.path(dir_forecast, "model_performance.csv")

write.csv(ds_forecast_long, file = path_forecast_long,   row.names = FALSE)
write.csv(ds_forecast_wide,  file = path_forecast_wide,  row.names = FALSE)
write.csv(ds_backtest,       file = path_backtest,       row.names = FALSE)
write.csv(model_performance, file = path_performance,    row.names = FALSE)

cat("\n  Forecast artifacts written:\n")
cat("    forecast_long.csv  :",      nrow(ds_forecast_long),  "rows\n")
cat("    forecast_wide.csv  :",      nrow(ds_forecast_wide),  "rows x",
    ncol(ds_forecast_wide), "cols\n")
cat("    backtest_comparison.csv :", nrow(ds_backtest),        "rows\n")
cat("    model_performance.csv  :",  nrow(model_performance),  "rows\n")

# Round-trip verification: reload each CSV and check row counts
for (p in c(path_forecast_long, path_forecast_wide, path_backtest, path_performance)) {
  rt <- read.csv(p)
  expected <- switch(basename(p),
    "forecast_long.csv"        = nrow(ds_forecast_long),
    "forecast_wide.csv"        = nrow(ds_forecast_wide),
    "backtest_comparison.csv"  = nrow(ds_backtest),
    "model_performance.csv"    = nrow(model_performance)
  )
  checkmate::assert_true(nrow(rt) == expected,
    .var.name = paste0("round-trip row count: ", basename(p)))
}
cat("  Round-trip verification: all CSV files reload correctly.\n")

# ==============================================================================
# SECTION 9: WRITE FORECAST MANIFEST
# ==============================================================================

# ---- forecast-manifest -------------------------------------------------------
cat("\n", strrep("=", 70), "\n")
cat("SECTION 9: Write Forecast Manifest (YAML)\n")
cat(strrep("=", 70), "\n")

# Compute forecast hash over all four output CSVs combined
csv_contents <- paste0(
  paste(readLines(path_forecast_long), collapse = "\n"),
  paste(readLines(path_forecast_wide), collapse = "\n"),
  paste(readLines(path_backtest),      collapse = "\n"),
  paste(readLines(path_performance),   collapse = "\n")
)
forecast_hash <- digest::digest(csv_contents, algo = "md5")

forecast_manifest <- list(
  forecast_hash      = forecast_hash,
  forge_hash_consumed = forge_hash,
  mint_train_forecast_chain = "versioned by focal_date; changing focal_date invalidates all Mint/Train/Forecast artifacts",

  forecast_parameters = list(
    focal_date              = as.character(focal_date),
    first_forecast_month    = format(first_forecast_date),
    last_forecast_month     = format(max(forecast_dates)),
    forecast_horizon_months = forecast_horizon,
    random_seed             = random_seed,
    transform               = "log (EDA-001); back-transformed via exp()"
  ),

  models_forecasted = lapply(seq_len(nrow(model_registry)), function(i) {
    list(
      model_id   = model_registry$model_id[i],
      tier       = model_registry$tier[i],
      tier_label = model_registry$tier_label[i],
      rds_file   = model_registry$rds_filename[i],
      backtest_rmse = model_registry$backtest_rmse[i],
      backtest_mape = model_registry$backtest_mape[i]
    )
  }),

  artifacts = list(
    forecast_long = list(
      file        = "forecast_long.csv",
      description = "Long format: one row per model x forecast month; point forecast + intervals",
      n_rows      = nrow(ds_forecast_long),
      n_models    = nrow(model_registry),
      n_months    = forecast_horizon
    ),
    forecast_wide = list(
      file        = "forecast_wide.csv",
      description = "Wide format: one row per forecast month; models as column groups",
      n_rows      = nrow(ds_forecast_wide),
      n_cols      = ncol(ds_forecast_wide)
    ),
    backtest_comparison = list(
      file        = "backtest_comparison.csv",
      description = "In-sample fitted vs actual for test window; use for visual diagnostics only; see model_performance.csv for true hold-out metrics",
      n_rows      = nrow(ds_backtest),
      test_start  = format(test_start),
      test_end    = format(test_end)
    ),
    model_performance = list(
      file        = "model_performance.csv",
      description = "True hold-out backtest metrics (RMSE, MAE, MAPE) from 4-train-IS.R",
      n_rows      = nrow(model_performance)
    ),
    forecast_manifest = list(
      file        = "forecast_manifest.yml",
      description = "Lineage YAML linking Forecast artifacts to Mint forge_hash"
    )
  ),

  report_lane_notes = list(
    eda_context          = "analysis/eda-2/eda-2.html",
    forecast_report_path = "analysis/forecast-1/forecast-1.qmd (to be created)",
    recommended_plots    = c(
      "ggplot ribbon: date vs point_forecast + lo_95/hi_95 from forecast_long.csv",
      "ggplot facet_wrap: by tier_label for tier comparison",
      "ggplot actual-vs-fitted: date vs actual_caseload + fitted_caseload from backtest_comparison.csv",
      "kable table: model_performance.csv RMSE/MAE/MAPE side-by-side"
    )
  ),

  execution_timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)

path_manifest <- file.path(dir_forecast, "forecast_manifest.yml")
yaml::write_yaml(forecast_manifest, file = path_manifest)

cat("\n  forecast_manifest.yml written to:", path_manifest, "\n")
cat("  forecast_hash :", forecast_hash, "\n")
cat("  forge_hash    :", forge_hash, " (lineage bond from 3-mint-IS.R)\n")

# ==============================================================================
# SECTION 10: ARTIFACT SUMMARY & SESSION INFO
# ==============================================================================

# ---- session-info ------------------------------------------------------------
cat("\n", strrep("=", 70), "\n")
cat("SESSION INFO\n")
cat(strrep("=", 70), "\n")

duration     <- difftime(Sys.time(), script_start, units = "secs")
executed_at  <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

forecast_files <- list.files(dir_forecast, full.names = TRUE)
file_info      <- file.info(forecast_files)
artifact_table <- data.frame(
  file     = basename(forecast_files),
  size_kb  = round(file_info$size / 1024, 1),
  stringsAsFactors = FALSE
)

cat("\n  Forecast completed in", round(as.numeric(duration), 1), "seconds\n")
cat("  Executed:", executed_at, "\n")
cat("  forge_hash consumed:", forge_hash, "\n")
cat("  forecast_hash produced:", forecast_hash, "\n")

cat("\n  Artifacts saved to:", dir_forecast, "\n\n")
cat("  ", sprintf("%-32s %8s", "File", "Size (KB)"), "\n")
cat("  ", strrep("-", 42), "\n")
for (i in seq_len(nrow(artifact_table))) {
  cat("  ", sprintf("%-32s %8.1f", artifact_table$file[i],
                    artifact_table$size_kb[i]), "\n")
}
cat("  ", strrep("-", 42), "\n")
cat("  ", sprintf("%-32s %8.1f", "TOTAL", sum(artifact_table$size_kb)), "\n")

cat("\n  Tiers forecasted:\n")
for (i in seq_len(nrow(model_registry))) {
  cat("    Tier", model_registry$tier[i], ":", model_registry$tier_label[i],
      "| RMSE =", model_registry$backtest_rmse[i],
      "| MAPE =", model_registry$backtest_mape[i], "%\n")
}

cat("\n  Mint-Train-Forecast lineage chain:\n")
cat("    forge_hash  :", forge_hash, "(from 3-mint-IS.R)\n")
cat("    forecast_hash:", forecast_hash, "(this run)\n")

cat("\n  Ready for Report lane (6-report-IS.qmd)\n")
cat("    -> Load forecast_long.csv        for ribbon forecast plots\n")
cat("    -> Load forecast_wide.csv        for comparison tables\n")
cat("    -> Load backtest_comparison.csv  for residual diagnostic plots\n")
cat("    -> Load model_performance.csv    for RMSE/MAE/MAPE summary table\n")
cat("    -> Load forecast_manifest.yml    for provenance metadata\n")

sessionInfo()
