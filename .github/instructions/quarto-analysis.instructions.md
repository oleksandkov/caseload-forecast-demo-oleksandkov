---
description: "Use when handling any file from the analysis/ folder for inclusion in the website. Describes the structure of analysis/, how to use rendered HTML outputs, and how to select figures (prints vs figure-png-iso)."
applyTo: "analysis/**"
---

# Quarto Analysis Instructions

## analysis/ Folder Structure

```
analysis/
├─ eda-1/
│  ├─ eda-1.R          — development script; produces datasets and saves PNG figures
│  ├─ eda-1.qmd        — Quarto report that pulls labeled chunks from eda-1.R
│  ├─ eda-1.html       — rendered report output (preferred for website inclusion)
│  ├─ prints/          — high-quality exported PNG figures (use for website visuals)
│  └─ figure-png-iso/  — Quarto-generated figure files (used during rendering only)
│
├─ eda-2/
│  ├─ eda-2.R          — caseload time-series EDA
│  ├─ eda-2.qmd        — report publication layer
│  └─ prints/          — exported figures
│
└─ report-1/
   ├─ report-1.R       — reporting computation layer (Lane 5 artifacts)
   ├─ report-1.qmd     — final Lane 6 report document
   └─ prompt-start.md  — authoring brief (do not include in website)
```

## Rules for Website Inclusion

### Page Semantics from Configuration

- Treat each file resolved from a `###` block in `configuration.prompt.md` as a page candidate for that section.
- If a `###` block resolves to multiple files, create multiple pages and wire them into the same navbar/sidebar section.
- Do not expose raw source path strings (for example `./philosophy/FIDES-example.md`) in rendered page content or visible headings/navigation labels.
- Use the source file content as the page body, and derive display labels from frontmatter `title` or first heading.

### Default Rendering Behavior (QMD First)

When a `###` section references an analysis unit (e.g., `analysis/EDA-2` or `analysis/report-1`):

1. **Default mode (required):** use the `.qmd` source as the canonical content and render it to HTML for website inclusion.
   - Treat the rendered output from the `.qmd` as the page content used in the section.
   - Use existing rendered `.html` files only as supporting artifacts unless the user explicitly asks otherwise.
    - The short description must summarize the report in 1–2 lines (do not show source file paths in that text).
   - Validate that the link resolves correctly from the generated page location (no broken relative paths).
   - Keep the wrapper/minimal page in the same website theme and layout settings as the rest of the site.
2. **User override mode:** if the user explicitly asks to use the already existing `.html` page, create a minimal page that contains:
   - page title,
   - short description,
   - a direct link to the existing HTML URL.
   In this override mode, do not replace the existing HTML file content.

### Theme and Style Consistency (All Pages)

- All HTML pages included in the website must use a single consistent theme and shared visual settings.
- This rule is mandatory for analysis reports: typography, spacing, colors, heading styles, and TOC behavior should match the website-wide defaults.
- If an included analysis HTML visually diverges from the site theme, normalize presentation via the embedding/page wrapper settings so the final website experience remains consistent.

### Figure Selection

- **For website visuals**: prefer figures from `prints/` — they are high-quality, publication-ready PNGs.
- This preference also applies when equivalent figures exist in other render-output folders; use `prints/` first.
- **Avoid** using `figure-png-iso/` for the website — these are intermediate Quarto render artifacts.
- **Avoid** including `eda-1_cache/` or any `*_cache/` directories — these are internal knitr/Quarto caches.

### Sync on Source Changes

- On every website build run, re-scan referenced analysis folders.
- If a source page or figure changed, replace the copied page/asset in `frontend-*/`.
- If a new matching file is added in a referenced analysis folder, add it to the website in the same run.

### Self-Contained Asset Handling

- Copy all referenced analysis assets (especially `prints/*.png`) into the website source tree under `frontend-*/<section>/assets/`.
- Update page links/image paths to point to copied assets, so rendered output does not depend on external paths.
- Do not rely on `analysis/` runtime paths at final site view time.

### User Notes Override

Always check the user notes in `configuration.prompt.md` for any per-file instructions. If the user specifies which prints to include or requests changes to the HTML output, apply those changes to the site page — not to the source `.html` file.

### Files to Always Exclude

- `README.md` files inside analysis subfolders
- `prompt-start.md`
- `*.R` script files
- `*_cache/` directories
- `data-local/` directories

## Execution Pipeline Reference

For understanding dependencies when regeneration is needed:

```
eda-1.R → eda-1.qmd → eda-1.html
eda-2.R → eda-2.qmd → (eda-2.html)
report-1.R → report-1.qmd → report-1.html
```

Full pipeline: Ferry → Ellis → (EDA-2 advisory) → Mint → Train → Forecast → Report
