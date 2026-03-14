# Two-Agent Publishing System: Editor + Publisher (Completed Spec v2)

## Why this v2 exists

This version completes the original concept by combining:

1. Your decisions from `edit-publish-agents.md`.
2. Operational constraints and behavior from `.github/agents/agent-presenter.agent.md`.

The result is a practical, implementable two-agent model that works **today** under current Copilot workflow constraints.

---

## One-line architecture

- **Editor** decides and prepares.
- **Publisher** executes and renders.
- **Human** owns cross-agent handoff and final configuration authoring.

---

## Final role split

### Editor Agent (human-facing, creative)

Responsibilities:
- Read `description.prompt.md` and repository context.
- Help the human choose output format/toolchain (Quarto preset, HTML workflow, etc.).
- Curate pages/sections/narrative and prepare `content/` for the selected format.
- Suggest schemas/templates and best options.

Hard boundaries:
- Does **not** run final publish/render pipeline.
- Does **not** own deterministic build execution.
- In this workflow, does **not** own final `configuration.prompt.md` authorship (human-owned).

### Publisher Agent (non-human-facing, deterministic)

Responsibilities:
- Read `content/` + `configuration.prompt.md`.
- Execute format-specific build.
- Produce `_site/`.
- Enforce deterministic parsing/behavior for its format.

Hard boundaries:
- No editorial negotiation with the human.
- No open-ended creative rewriting.
- If blocked or ambiguous: write `questions.prompt.md` and stop.

---

## Mapping from current `Agent Presenter` to two-agent model

Current `Agent Presenter` mixes editorial and build execution. In v2, it is split logically:

- **Editor absorbs**: discovery, section/page planning, file selection strategy, format choice, content prep.
- **Publisher absorbs**: scaffolding, `_quarto.yml` generation, explicit `project.render`, asset sync, render, reconciliation, `.gitignore` hygiene.

This preserves proven behavior while separating concerns.

---

## Workflow (implemented in current platform)

1. Human creates/updates `description.prompt.md`.
2. Editor session decides structure + format and prepares `content/`.
3. Human writes/updates `configuration.prompt.md` in schema expected by chosen Publisher.
4. Human manually runs corresponding Publisher.
5. Publisher builds `_site/` deterministically.
6. If blocked, Publisher writes `questions.prompt.md`.
7. Human resolves questions with Editor, updates files, and manually re-runs Publisher.

This is the supported fallback to the ideal (automatic same-conversation agent switching with memory continuity).

---

## Contracts between agents

## A) Workspace contract (per `_frontend-*`)

Each frontend workspace is independent and contains:

- `description.prompt.md` (editorial seed)
- `content/` (editor output, format-prepared)
- `configuration.prompt.md` (human-authored, publisher-specific)
- `questions.prompt.md` (optional, publisher-generated clarifications)
- `_site/` (publisher output)

No cross-workspace shared `content/` by default.

## B) `description.prompt.md` contract

- Human-owned input.
- Read by Editor.
- Optional for Publisher.
- Purpose: goals, audience, candidate files, constraints, preferred formats.

## C) `configuration.prompt.md` contract

- **Format-specific** (not universal).
- One schema per Publisher.
- May include optional human-readable preamble, but must include a deterministic machine-parseable block.

Minimum deterministic fields for Quarto-style Publisher:
- output format identifier,
- navigation structure (navbar/sidebar where applicable),
- ordered section-to-page mapping,
- per-page source mapping,
- theme/footer/repo-link options,
- inclusion/exclusion rules.

## D) `questions.prompt.md` contract

Publisher writes this when blocked by missing or ambiguous input.

Recommended structure:
- issue id,
- blocking reason,
- file(s) involved,
- expected decision options,
- required user action,
- timestamp/status.

---

## Format strategy (your decision implemented)

- Editor is generic and reusable.
- Editor uses **format-specific preparation instructions** once format is chosen.
- User manually selects matching Publisher.
- Each Publisher may define its own configuration schema.

Therefore, `content/` is **format-aware**, not fully format-neutral.

---

## Publisher scope for “simple modifications”

Allowed (if declared by Publisher schema/config):
- structure wiring (nav, pages, folders),
- metadata/frontmatter generation,
- theme/footer/repo references,
- deterministic post-render adjustments (including targeted HTML-level changes if explicitly permitted by that Publisher).

Not allowed:
- open-ended editorial rewriting,
- silent semantic changes beyond declared rules.

If uncertain, Publisher must stop and emit `questions.prompt.md`.

---

## Required deterministic behavior for Quarto-oriented Publisher

Borrowed from current `agent-presenter` expectations:

1. Never modify `configuration.prompt.md`.
2. Build `_quarto.yml` from config (no default scaffold assumptions).
3. Maintain explicit `project.render` list (no wildcard rendering of unrelated files).
4. Resolve section/page mapping from config hierarchy deterministically.
5. Sync source deltas on every run (changed/new sources reflected in frontend workspace).
6. Reconcile at end: add missing, remove extras, then re-render if needed.
7. Handle missing source files as warnings (skip, do not crash entire run).
8. Copy needed assets for self-contained output where required.
9. Ensure root `.gitignore` includes frontend build/cache artifacts.

---

## Open implementation note: single-agent compatibility mode

Until native dynamic agent switching exists, teams may still run a single orchestrator for convenience.
In that case, treat it as an implementation wrapper that internally follows this split:

- editor-mode phase,
- human checkpoint,
- publisher-mode phase.

This preserves architecture boundaries while remaining operationally practical.

---

## Decision log (resolved from your answers)

1. `configuration.prompt.md` is publisher-specific.
2. Human writes final `configuration.prompt.md`.
3. Editor prepares `content/` for chosen format.
4. Publisher does not chat with human directly.
5. Error loop uses `questions.prompt.md`.
6. Re-run is manual and user-initiated.
7. Multiple `_frontend-*` workspaces are independent.
8. Prompts should remain generic; avoid hard-coded project vocabulary.
9. Editor has full project context access; Publisher should primarily rely on contract files.

---

## Final summary

This completed v2 design is a **contract-first, manual-handoff two-agent system**:

- creative/interactive decisions happen in Editor,
- deterministic rendering happens in format-specific Publisher,
- contract files mediate handoffs,
- and current `Agent Presenter` execution strengths are preserved through a clean split.
