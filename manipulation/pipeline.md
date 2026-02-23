# Pipeline Execution Guide

**Purpose**: Documentation for executing data manipulation scripts in the caseload-forecast-demo project.

**Last Updated**: 2025-02-18

---

## Overview

This document describes the execution model for data manipulation scripts in this project. Scripts are organized into two categories:

1. **Non-Flow Scripts**: One-time setup or ad-hoc operations
2. **Flow Scripts**: Reproducible pipeline steps orchestrated by `./flow.R`

## Execution Philosophy

### To Execute This Project: Run `./flow.R`

The single command that reproduces all project outputs:

```r
source("./flow.R")
```

Or from terminal:

```bash
Rscript flow.R
```

**What Happens**: The `flow.R` script executes all pipeline steps defined in the `ds_rail` tibble in sequential order, handling:
- Data import (ferry lanes)
- Data transformation (ellis lanes) 
- Analysis scripts
- Report generation (Quarto documents)
- Error logging and validation

### Non-Flow Scripts: Setup and Experimentation

Scripts in `./manipulation/` that are **NOT** listed in `flow.R` serve supporting roles:
- **Setup**: Prepare data assets or infrastructure (e.g., `create-data-assets.R`)
- **Examples**: Demonstrate patterns (e.g., `ferry-lane-example.R`, `ellis-lane-example.R`)
- **Prototypes**: Experimental code being tested before integration into flow
- **Utilities**: Ad-hoc analysis or data inspection scripts

These scripts are documented here for understanding but are **not part of the reproducible pipeline**.

---

## Non-Flow Scripts

### `create-data-assets.R`

**Category**: One-Time Setup  
**Status**: Run before first pipeline execution  
**Purpose**: Prepare test data sources for multi-source ferry pattern demonstration

#### What It Does

Creates two data assets from the Open Alberta CSV file to enable testing of the multi-source ferry pattern (`1-ferry.R`):

1. **SQLite database**: `./data-public/raw/open-data-is-sep-2025.sqlite`
   - Table: `open_data_is_sep_2025`
   - Contents: Income Support aggregated data (April 2005 - Sept 2025)

2. **SQL Server table**: `RESEARCH_PROJECT_CACHE_UAT.AMLdemo.open_data_is_sep_2025`
   - Location: Remote database via ODBC
   - Contents: Identical to SQLite (for source comparison testing)

#### Execution Flow

```
create-data-assets.R Workflow
═════════════════════════════════════════════════════════════════

INPUT:
  ./data-public/raw/is-aggregated-data-april-2005-sep-2025.csv
                              │
                              ▼
                    ┌──────────────────┐
                    │  Load CSV Data   │
                    │  • Skip title    │
                    │  • Clean names   │
                    │  • Select cols   │
                    └────────┬─────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
    ┌──────────────────┐         ┌──────────────────┐
    │  Write to SQLite │         │ Write to SQL Svr │
    │  • Local file    │         │ • Remote ODBC    │
    │  • Fast access   │         │ • Enterprise DB  │
    └────────┬─────────┘         └────────┬─────────┘
             │                            │
             ▼                            ▼
    ┌──────────────────┐         ┌──────────────────┐
    │ open-data-is-    │         │ (DSN).AMLdemo.   │
    │ sep-2025.sqlite  │         │ open_data_is_... │
    └──────────────────┘         └──────────────────┘

OUTPUTS:
  ✓ SQLite:     ./data-public/raw/open-data-is-sep-2025.sqlite
  ✓ SQL Server: RESEARCH_PROJECT_CACHE_UAT.AMLdemo.open_data_is_sep_2025
  ✓ Validation: Row count verification across all sources
```

#### When to Run

- **Initial setup**: Before first execution of `1-ferry.R`
- **Data refresh**: When Open Alberta updates the source CSV
- **Testing**: To reset data assets to known good state

#### Dependencies

```r
# Required packages
library(magrittr)
library(dplyr)
library(readr)
library(janitor)
library(DBI)
library(RSQLite)
library(odbc)

# Required infrastructure
# - ODBC DSN configured: RESEARCH_PROJECT_CACHE_UAT
# - SQL Server schema exists: AMLdemo
# - Sufficient disk space for SQLite file (~5MB)
```

#### Validation

The script performs automatic validation:
- **Dimension check**: All sources have identical row/column counts
- **Column check**: Verify consistent column names
- **Row count**: Confirm matching record counts after write

Success message:
```
✅ VALIDATION PASSED: All tables have identical row counts
```

#### Why This Is Non-Flow

This script is **infrastructure setup**, not reproducible analysis:
- Run once to establish data assets
- Not needed on every pipeline execution
- Creates resources that ferry lanes consume
- Similar to installing packages or configuring database connections

---

### `ferry-lane-example.R` and `ellis-lane-example.R`

**Category**: Pattern Examples  
**Status**: Educational reference  
**Purpose**: Demonstrate ferry and ellis pattern implementation

These scripts use the `mtcars` dataset to illustrate:
- **Ferry**: Transporting data from WAREHOUSE to CACHE with minimal transformation
- **Ellis**: Cleaning and standardizing data to create analysis-ready datasets

See [Pattern Philosophy](README.md#ferry-and-ellis-patterns-philosophy-and-implementation-guide) in README.md for detailed pattern documentation.

**Why These Are Non-Flow**: They are self-contained examples for learning, not part of the project's analytical pipeline. Think of them as "unit tests" for pattern understanding.

---

## Flow Scripts

Scripts listed in the `ds_rail` tibble within `./flow.R` constitute the **reproducible pipeline**. These are executed in order when running `source("./flow.R")`.

### Current Pipeline Configuration

```r
# From flow.R - ds_rail definition
ds_rail  <- tibble::tribble(
  ~fx         , ~path,
  
  # PHASE 1: DATA IMPORT & PREPARATION
  "run_r"     , "manipulation/1-ferry.R",
  
  # PHASE 2: ANALYSIS SCRIPTS
  # (to be added)
  
  # PHASE 3: REPORTS & DOCUMENTATION  
  "run_qmd"   , "analysis/eda-1/eda-1.qmd",
  
  # PHASE 4: ADVANCED REPORTS (future)
  # (to be added)
)
```

---

### `1-ferry.R` - Multi-Source Data Transport

**Phase**: Data Import & Preparation  
**Pattern**: Ferry (Zero semantic transformation)  
**Status**: Active in pipeline

#### Purpose

Demonstrate and validate that Income Support open data can be loaded from **four equivalent sources**, establishing source interchangeability for flexible deployment:

1. **URL**: Open Alberta API endpoint (production source)
2. **CSV**: Local cached file (offline development)
3. **SQLite**: Local database (fast access, version control friendly)
4. **SQL Server**: Enterprise database (production alternative)

#### Ferry Pattern Implementation

```
1-ferry.R: Multi-Source Data Transport
═════════════════════════════════════════════════════════════════

SOURCES (4 Equivalent Sources):

┌────────────────────┐
│   1. URL Source    │  Open Alberta API
│  (Internet)        │  https://open.alberta.ca/.../is-aggregated...
└──────────┬─────────┘
           │
           ▼ load_from_url()
┌────────────────────┐
│  ds_url            │  read_csv(url)
└──────────┬─────────┘
           │
           │
┌────────────────────┐
│   2. CSV Source    │  Local cache
│  (File)            │  ./data-public/raw/is-aggregated-data...
└──────────┬─────────┘
           │
           ▼ load_from_csv()
┌────────────────────┐
│  ds_csv            │  read_csv(path)
└──────────┬─────────┘
           │
           │
┌────────────────────┐
│  3. SQLite Source  │  Local database
│  (Database)        │  ./data-public/raw/open-data-is-sep-2025.sqlite
└──────────┬─────────┘
           │
           ▼ load_from_sqlite()
┌────────────────────┐
│  ds_sqlite         │  DBI::dbConnect(SQLite)
└──────────┬─────────┘
           │
           │
┌────────────────────┐
│ 4. SQL Server Src  │  Remote enterprise database
│  (ODBC)            │  RESEARCH_PROJECT_CACHE_UAT
└──────────┬─────────┘
           │
           ▼ load_from_sqlserver()
┌────────────────────┐
│  ds_sqlserver      │  DBI::dbConnect(odbc)
└──────────┬─────────┘
           │
           │
           ▼ validate_identity()
┌────────────────────────────────────────┐
│  VALIDATION CHECKS:                    │
│  ✓ Dimensions identical                │
│  ✓ Column names identical              │
│  ✓ Row-by-row data identical           │
│  ✓ Source interchangeability confirmed │
└──────────────────┬─────────────────────┘
                   │
                   ▼ save_to_output()
┌────────────────────────────────────────┐
│  OUTPUT (Staging):                     │
│  ./data-private/derived/               │
│    open-data-is-1.sqlite               │
│                                        │
│  Table: open_data_is_raw               │
│  Rows: ~50,000 (varies by data date)   │
│  Cols: 5 (ref_date, geography,         │
│           measure_type, measure, value)│
└────────────────────────────────────────┘
```

#### Transformations Applied

**Permitted** (technical transport only):
- Column name cleaning: `janitor::clean_names()` (spaces → underscores, lowercase)
- Column selection: Keep only 5 essential columns
- Skip header row: `skip = 1` (Open Alberta CSV has title row)

**Forbidden** (ferry principle):
- No factor recoding
- No value transformation
- No derived variables
- No filtering or aggregation

#### Output

**File**: `./data-private/derived/open-data-is-1.sqlite`  
**Table**: `open_data_is_raw`  
**Schema**:
```
ref_date       chr   "2005-04", "2005-05", ... (YY-Mon format)
geography      chr   "Alberta", "Calgary", "Edmonton", ...
measure_type   chr   "Active clients", "Intake", "Exits"
measure        chr   "Persons", "Case count", "Benefit units"
value          chr   "1234", "567", ... (numbers as strings, may have commas)
```

**Note**: This is **raw staging data**. The ellis lane (future `2-ellis.R`) will:
- Parse dates properly
- Convert value to numeric
- Recode factors to project taxonomy
- Create derived features (fiscal year, lags, etc.)

#### Validation Output

```bash
=== VALIDATING SOURCE IDENTITY ===

Dimensions:
      URL     CSV  SQLite SQLServer 
"50000 × 5" "50000 × 5" "50000 × 5" "50000 × 5" 

✓ All sources have identical dimensions
✓ All sources have identical column names
✓ All sources produce identical datasets
✓ Sources are interchangeable
```

#### Why This Matters

**Source flexibility** enables:
- **Development**: Work offline with CSV/SQLite
- **Production**: Use URL or SQL Server for fresh data
- **Testing**: Quickly swap sources without code changes
- **Disaster recovery**: Multiple backup options
- **Cloud migration**: Validate SQL Server integration before Azure ML deployment

#### Next Steps in Pipeline

1. **Ellis lane** (`2-ellis.R`): Transform raw staging to analysis-ready
2. **EDA reports** (`analysis/eda-2/`): Exploratory time-series analysis
3. **Mint lane** (`3-mint-IS.R`): Prepare model-ready data slices
4. **Train lane** (`4-train-IS.R`): Estimate Tier 1–2 models
5. **Forecast lane** (`5-forecast-IS.R`): Generate 24-month horizon predictions — see below

---

### `5-forecast-IS.R` — 24-Month Horizon Forecast Generation

**Phase**: Forecast (Pattern 5 of 6)  
**Pattern**: Forecast (consumes Train `.rds` objects, produces prediction artifacts)  
**Status**: Active in pipeline  
**Execution time**: ~3 seconds

#### Purpose

Generate 24-month forward projections and backtest diagnostics for all trained model
tiers, producing structured artifacts that the Report lane consumes directly without
additional computation.

#### Input

| Source | File | Description |
|--------|------|--------------|
| Train output | `data-private/derived/models/model_registry.csv` | Model metadata, paths, backtest metrics |
| Train output | `data-private/derived/models/tier_1_snaive.rds` | Seasonal naive model (fitted on ts_full) |
| Train output | `data-private/derived/models/tier_2_arima.rds` | ARIMA model (fitted on ts_full) |
| Mint output | `data-private/derived/forge/ds_full.parquet` | Full 246-month series (date, caseload, y) |
| Mint output | `data-private/derived/forge/forge_manifest.yml` | forge_hash for lineage validation |

#### Output

All artifacts written to `./data-private/derived/forecast/`:

| File | Rows | Description |
|------|------|-------------|
| `forecast_long.csv` | 48 | Long format: one row per model × forecast month; point + 80%/95% intervals |
| `forecast_wide.csv` | 24 | Wide format: one forecast month per row; models as column groups |
| `backtest_comparison.csv` | 48 | In-sample fitted vs actual for test window (Oct 2023–Sep 2025) |
| `model_performance.csv` | 2 | RMSE, MAE, MAPE from Train lane hold-out evaluation |
| `forecast_manifest.yml` | — | Lineage YAML: forecast_hash, forge_hash consumed, artifact inventory |

**Forecast window**: Oct 2025 – Sep 2027 (24 months from focal_date)

#### Forecast Columns (forecast_long.csv)

```
date             Date    Forecast month (first of month)
year             int     Calendar year
month            int     Month number (1–12)
fiscal_year      chr     Alberta FY label (e.g. "FY 2025-26")
month_label      chr     Readable label (e.g. "Oct 2025")
model_id         chr     "tier_1_snaive" | "tier_2_arima"
tier             int     1 | 2
tier_label       chr     "Naive Baseline" | "ARIMA"
point_forecast   num     Original caseload scale (exp back-transformed)
lo_80 / hi_80    num     80% prediction interval bounds
lo_95 / hi_95    num     95% prediction interval bounds
```

#### Lineage Validation

Section 3 validates `forge_hash` from the model registry matches the current
`forge_manifest.yml`. If Mint was re-run after Training, the script stops with an
explicit error message instructing the analyst to re-run lanes 3 and 4 first.

#### Forbidden

- Refitting models (no `auto.arima()` or `snaive()` calls in this script)
- Reading Ellis output directly
- Producing new data transformations

#### Report Lane Usage

```r
# In 6-report-IS.qmd:
dir_fc <- config$directories$forecast
forecast_long     <- read.csv(file.path(dir_fc, "forecast_long.csv"))
forecast_wide     <- read.csv(file.path(dir_fc, "forecast_wide.csv"))
backtest          <- read.csv(file.path(dir_fc, "backtest_comparison.csv"))
performance       <- read.csv(file.path(dir_fc, "model_performance.csv"))
fc_manifest       <- yaml::read_yaml(file.path(dir_fc, "forecast_manifest.yml"))

# Ribbon forecast plot:
ggplot(forecast_long, aes(x = as.Date(date), y = point_forecast,
                           colour = tier_label, fill = tier_label)) +
  geom_ribbon(aes(ymin = lo_95, ymax = hi_95), alpha = 0.15) +
  geom_ribbon(aes(ymin = lo_80, ymax = hi_80), alpha = 0.25) +
  geom_line() +
  facet_wrap(~tier_label) +
  labs(title = "Alberta Income Support: 24-Month Forecast",
       x = NULL, y = "Active Caseload") +
  theme_bw()
```

---

## Adding New Scripts to the Pipeline

### Step 1: Create Script in `./manipulation/`

Follow pattern conventions:
- **Ferry lanes**: `{N}-ferry-{source}.R` (e.g., `3-ferry-LMTA.R`)
- **Ellis lanes**: `{N}-ellis-{entity}.R` (e.g., `4-ellis-customer.R`)
- **Mint lanes**: `{N}-mint-{target}.R` (e.g., `3-mint-IS.R`)
- **Train lanes**: `{N}-train-{model}.R` (e.g., `4-train-IS.R`)
- **Forecast lanes**: `{N}-forecast-{target}.R` (e.g., `5-forecast-IS.R`)
- **Report lanes**: `{N}-report-{target}.qmd` (e.g., `6-report-IS.qmd`)

### Step 2: Add to `flow.R`

Edit the `ds_rail` tibble:

```r
ds_rail  <- tibble::tribble(
  ~fx         , ~path,
  
  # PHASE 1: FERRY
  "run_r"     , "manipulation/1-ferry.R",
  
  # PHASE 2: ELLIS
  "run_r"     , "manipulation/2-ellis.R",              # NEW
  
  # PHASE 3: MINT
  "run_r"     , "manipulation/3-mint-IS.R",            # NEW
  
  # PHASE 4: TRAIN
  "run_r"     , "manipulation/4-train-IS.R",           # NEW
  
  # PHASE 5: FORECAST
  "run_r"     , "manipulation/5-forecast-IS.R",        # NEW
  
  # PHASE 6: REPORT
  "run_qmd"   , "analysis/report-1/report-1.qmd",      # NEW
)
```

### Step 3: Test Execution

Run the entire flow:

```r
source("./flow.R")
```

Or test your script individually first:

```r
source("./manipulation/2-ellis.R")
```

### Step 4: Update This Documentation

Add script documentation to this file under **Flow Scripts** section.

---

## Execution Checklist

### First-Time Setup

- [ ] Install required R packages: `renv::restore()`
- [ ] Download or verify CSV exists: `./data-public/raw/is-aggregated-data-april-2005-sep-2025.csv`
- [ ] Run: `source("./manipulation/nonflow/create-data-assets.R")` to create SQLite and SQL Server assets
- [ ] Verify ODBC connection (if using SQL Server): `DBI::dbConnect(odbc::odbc(), dsn = "RESEARCH_PROJECT_CACHE_UAT")`
- [ ] Create output directories: `./data-private/derived/`, `./data-private/raw/`

### Regular Execution

```r
# From R console (recommended)
source("./flow.R")

# From terminal
Rscript flow.R

# From VS Code task
# Tasks: Run Task > Run Ferry Lane 1
```

### Troubleshooting

**Error**: `Source CSV not found`  
**Fix**: Download from Open Alberta or check file path in `create-data-assets.R`

**Error**: `ODBC connection failed`  
**Fix**: Verify DSN configuration in Windows ODBC Data Source Administrator

**Error**: `SQLite file not found`  
**Fix**: Run `create-data-assets.R` to generate local database

**Error**: `flow.R script error at step X`  
**Fix**: Run individual script to see detailed error: `source("./manipulation/X.R")`

---

## Visual Pipeline Summary

```
Complete Pipeline Flow (6-Pattern Structure)
═════════════════════════════════════════════════════════════════

SETUP PHASE (Non-Flow, Run Once):
┌────────────────────────────────────────────┐
│  create-data-assets.R                      │
│  ↓                                         │
│  Creates: SQLite + SQL Server sources      │
└──────────────────┬─────────────────────────┘
                   │
                   ▼
FLOW PHASE (Reproducible, Run ./flow.R):
┌────────────────────────────────────────────┐
│  1. FERRY: 1-ferry.R                       │
│  ↓                                         │
│  Load: URL | CSV | SQLite | SQL Server     │
│  Validate: Source identity                 │
│  Output: open-data-is-1.sqlite             │
└──────────────────┬─────────────────────────┘
                   │
                   ▼
┌────────────────────────────────────────────┐
│  2. ELLIS: 2-ellis.R                       │
│  ↓                                         │
│  Transform: Parse dates, clean values      │
│  Create: Derived features                  │
│  Output: Analysis-ready + CACHE-manifest   │
└──────────────────┬─────────────────────────┘
                   │
          ┌───────┴───────┐
          │  EDA (advisory) │  analysis/eda-2/eda-2.qmd
          │  Not in flow.R  │  Informs Mint decisions
          └───────┬───────┘
                   │ (analyst judgment)
                   ▼
┌────────────────────────────────────────────┐
│  3. MINT: 3-mint-IS.R                      │
│  ↓                                         │
│  Apply: train/test split, log transform    │
│  Build: ts objects, xreg matrices           │
│  Output: forge/ dir + forge_manifest.yml   │
└──────────────────┬─────────────────────────┘
                   │
                   ▼
┌────────────────────────────────────────────┐
│  4. TRAIN: 4-train-IS.R                    │
│  ↓                                         │
│  Estimate: Naive, ARIMA, ARIMA+xreg       │
│  Backtest: 24-month held-out window        │
│  Output: models/ dir + model_registry.csv  │
└──────────────────┬─────────────────────────┘
                   │
                   ▼
┌────────────────────────────────────────────┐
│  5. FORECAST: 5-forecast-IS.R              │
│  ↓                                         │
│  Generate: 24-month point + intervals      │
│  Compare: All tiers side-by-side            │
│  Output: CSV + Quarto report               │
└──────────────────┬─────────────────────────┘
                   │
                   ▼
┌────────────────────────────────────────────┐
│  6. REPORT: 6-report-IS.qmd                │
│  ↓                                         │
│  Combine: EDA + performance + forecasts    │
│  Output: Static HTML for stakeholders      │
└────────────────────────────────────────────┘
```

Mint-Train-Forecast form a versioned lineage keyed by `focal_date`.
See `./ai/project/method.md` for the Mint-Train-Forecast Lineage section.

---

## Lane Naming Convention (All 6 Patterns)

| Pattern | Naming | Example |
|---------|--------|---------|
| Ferry | `{n}-ferry-{source}.R` | `1-ferry.R`, `1-ferry-IS.R` |
| Ellis | `{n}-ellis-{entity}.R` | `2-ellis.R`, `2-ellis-IS.R` |
| Mint | `{n}-mint-{target}.R` | `3-mint-IS.R` |
| Train | `{n}-train-{model}.R` | `4-train-IS.R` |
| Forecast | `{n}-forecast-{target}.R` | `5-forecast-IS.R` |
| Report | `{n}-report-{target}.qmd` | `6-report-IS.qmd` |

---

## Reference Materials

- **RAnalysisSkeleton**: [github.com/wibeasley/RAnalysisSkeleton](https://github.com/wibeasley/RAnalysisSkeleton)
  - Canonical implementation of flow pattern
  - Multiple data source examples
  - Report integration patterns

- **Ferry & Ellis Patterns**: See `./manipulation/README.md`
  - Detailed pattern philosophy
  - Transformation guidelines
  - AI implementation instructions

- **Project Mission**: See `./ai/project/mission.md`
  - Project objectives and success metrics
  - Non-goals and scope boundaries
  - Cloud migration strategy

- **Project Glossary**: See `./ai/project/glossary.md`
  - Ferry and Ellis pattern definitions
  - Data pipeline terminology
  - Azure ML terminology

---

## Maintenance Notes

**Last Pipeline Execution**: 2026-02-23  
**Scripts in Flow**: 5 (1-ferry, 2-ellis, 3-mint-IS, 4-train-IS, 5-forecast-IS)  
**Scripts Documented**: 3 non-flow, 2 flow (1-ferry, 5-forecast-IS)  
**Next Addition**: `6-report-IS.qmd` — Static HTML report combining EDA, backtesting diagnostics, and 24-month forecast visualisations

**Update Frequency**: Update this document when:
- Adding new scripts to `flow.R`
- Changing script execution order
- Modifying script dependencies
- Creating new non-flow setup scripts

---

*For questions or issues, refer to project documentation in `./ai/` or contact project maintainer.*
