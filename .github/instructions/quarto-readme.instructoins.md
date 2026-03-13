---
description: "Use when creating or updating the website index page from the project README with user-note-aware adaptation."
applyTo: "frontend-*/**"
---

# Quarto README Index Instructions

## Purpose

When generating the website landing/index page, use the root `README.md` as the primary source and convert/adapt it into a Quarto page suitable for the site.

## Rules

1. Build the index page from a transformed copy of root `README.md` (do not edit the original source README).
2. Apply any user notes found above the first `#` metadata line in `frontend-*/configuration.prompt.md` (or `frontend-*/configuration.prompt.md`).
3. If no user notes are provided, tailor the transformed index content specifically to the pages referenced in `frontend-*/_quarto.yml`.
4. Preserve core project meaning; rework structure/presentation for website readability only.
5. Keep links, sectioning, and navigation context aligned with the current site map.

## Exclusions

- Do not expose sensitive local paths.
- Do not include raw build/debug instructions that are not relevant to site visitors.
- Do not alter non-index content unless explicitly requested.
