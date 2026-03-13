---
description: "Use when normalizing .md/.qmd/.html sources for Quarto website pages. Describes content-preserving Markdown transit pages and direct HTML embedding rules."
applyTo: "frontend-*/**"
---

# Quarto Transformer — Source Normalization for Website Pages

Before any `.md`, `.qmd`, or `.html` source is referenced in `_quarto.yml` or placed as a website page, it must be handled according to these rules.

This transformer also normalizes `.md` content sources into `.qmd` website pages so each configured file can be rendered consistently.

## When to Apply

Apply this instruction whenever:
- A configuration `###` section points to a `.qmd` file.
- A configuration `###` section points to a `.md` file.
- A file discovered via a folder glob has a `.qmd` extension.
- A file discovered via a folder glob has a `.md` extension.
- You are adding content from `analysis/` or `manipulation/` that is a `.qmd` file.

## Conversion Rules

### 0. `###` Means Website Pages

- Each file resolved inside a `### <Section>` block represents a page for that section.
- Build one output page per resolved source file.
- Never expose raw source path literals (for example `./philosophy/FIDES-example.md`) as visible body text, headings, or nav labels.
- Derive display labels from frontmatter `title` or first markdown heading; if missing, use a humanized filename stem.

### 1. Prefer Ready HTML Output

If a source has an existing rendered `.html` sibling (e.g., `eda-1.qmd` → `eda-1.html`, or `notes.md` → `notes.html`), **use that HTML directly in the website page**. Do not re-render unless instructed by the user.

When HTML is used, still copy required local assets for self-contained output.

### 1a. HTML Must Be Embedded Inline — Never via iframe

- Do **not** wrap report content in an `<iframe>`. Iframes produce HTML-inside-HTML and cause visual and rendering issues.
- Do **not** create "wrapper pages" that only contain links such as "Open the standalone report in a new tab".
- Do **not** produce HTML-inside-HTML link chains.

**Preferred approach — inline body embed:**
Extract the `<body>` content from the source HTML file and paste it directly into the Quarto page using a raw `{=html}` block:

```qmd
---
title: "Report Title"
format:
  html:
    page-layout: full
    toc: false
---

```{=html}
<!-- full <body> content of report.html pasted here -->
<div class="report-content">
  ... (content of report body) ...
</div>
```
```

This renders the report content as part of the page itself — no iframe, no redirect, no new tab.

**Fallback — plain link (only when inline embed is not feasible):**
If the source HTML is too large, or relies on isolated JS/CSS that would conflict with the site's own styles, and direct body inclusion is impractical, create a regular in-page link:

```markdown
[View the report](report.html)
```

- Do **not** add `target="_blank"` or any open-in-new-tab attribute. Opening in a new tab is poor user experience and must not be used.
- The link must resolve relative to the page's own location in `frontend-*/`.

### 1b. Normalize Markdown Sources — Preferred: Direct HTML Conversion

If the source file is `.md`, convert it directly to a standalone `.html` file using Pandoc (or an equivalent converter) and reference that `.html` file as the website page. This is the **preferred path** because it avoids re-render complexity and produces a ready-to-serve file.

```
pandoc source.md -o frontend-*/<section>/source.html --standalone
```

Use the resulting `.html` as the page entry in `_quarto.yml` (list it under `project.render` and reference it in the navbar).

**Fall back to the QMD transit approach only if direct HTML conversion fails or is not available:**
1. Create a `.qmd` transit page in `frontend-*/<section>/` using the same base name.
2. Preserve the full original markdown content without editorial rewriting.
3. Prefer including the original markdown content verbatim (or a lossless copy) so headings, lists, links, and code blocks remain unchanged.
4. Add minimal Quarto frontmatter if missing:

```yaml
---
title: "<derived from filename or first heading>"
---
```

When creating transit/wrapper pages, include source content without printing the source file path as an intro line.

### 2. Fallback for Sources Without Ready HTML

If no `.html` is available:
1. Copy the `.qmd` file to the target `frontend-*/<section>/` directory with the same base name but a `.qmd` extension — Quarto will render it natively.
2. Strip or comment out any R/Python code chunks that cannot be executed in the static site context, unless the site is configured for live computation.
3. Retain YAML frontmatter (`title`, `author`, `date`, `description`) and convert it to Quarto-compatible page frontmatter.

For `.md` sources without ready HTML, use the transit `.qmd` approach from section **1b**.

### 3. Frontmatter Normalisation

Ensure each converted page has at minimum:

```yaml
---
title: "<derived from filename or original frontmatter>"
---
```

Remove execution-only fields (`execute`, `knitr`, `jupyter`) that are not relevant to static rendering.

### 4. Figure References

- Figures referenced via `![](figure-png-iso/g1-1.png)` or `prints/` paths must be copied alongside the page file so relative paths remain valid.
- Prefer `prints/` sources when both `prints/` and `figure-png-iso/` represent the same figure.
- Update relative paths if the file is moved to a different directory depth.

### 5. Sync Behavior on Re-Runs

- Re-resolve configuration globs and explicit file lists every run.
- If source files changed, update transformed/copied files in `frontend-*/`.
- If new matching files are discovered, add new pages during the same run.

### 6. Do Not Modify Source Files

Never edit the original `.qmd` file in its source location. All transformations happen on copies placed inside `frontend-*/`.
