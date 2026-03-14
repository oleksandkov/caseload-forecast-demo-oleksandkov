# Two-Agent Publishing System: Editor + Publisher

## Overview

This document describes a proposed two-agent architecture for producing front-end websites from repository content. The design separates **editorial decisions** (what to publish and how to present it) from **publishing execution** (rendering the site in a specific format). This separation allows a single, reusable Editor agent to pair with multiple format-specific Publisher agents.

The conversation that motivated this design identified a concrete problem: the current single-agent approach (`agent-presenter`) mixes human-facing editorial interaction with format-specific rendering logic. Its prompts hard-code project-specific terms (e.g., the Ferry–Ellis–Mint pipeline names), making the agent difficult to reuse across projects or output formats.

---

## Roles

### Editor Agent

| Attribute       | Description |
|-----------------|-------------|
| **Purpose**     | Interface with the human user to make editorial decisions about website content, structure, and presentation. |
| **Input**       | A seed file (`description.prompt.md`) describing the website's purpose, candidate source files, and any initial preferences. |
| **Interaction** | Conversational. The Editor discusses options with the user: which files to include, how to organize sections, what narrative framing to use, and which output format/toolchain to target (Quarto preset, rendered Markdown, hand-coded HTML, etc.). |
| **Output**      | A `content/` folder inside the frontend workspace (`_frontend-*/`) containing all prepared assets (normalized Markdown/QMD files, images, data summaries) **plus** a `configuration.prompt.md` file that describes the exact build plan the Publisher will execute. |
| **Does NOT do** | Render or build the final site. All rendering is delegated to the Publisher. |

### Publisher Agent

| Attribute       | Description |
|-----------------|-------------|
| **Purpose**     | Execute a deterministic build of the website from the prepared content and configuration. |
| **Input**       | The `content/` folder and `configuration.prompt.md` produced by the Editor. |
| **Interaction** | **None with the human.** The Publisher reads its instructions from `configuration.prompt.md` and executes them. If it encounters something unexpected (missing file, ambiguous instruction, format conflict), it reports the issue back to the Editor, who raises it with the human. |
| **Output**      | A `_site/` folder containing the self-contained, rendered website. |
| **Does NOT do** | Make editorial choices, ask the human questions, or modify source content beyond what is specified in the configuration. |

---

## Workflow

```
┌──────────────────────────────────────────────────────────────┐
│  _frontend-*/                                                │
│                                                              │
│  1. description.prompt.md          (seed file, written by    │
│                                     human or bootstrapped)   │
│              │                                               │
│              ▼                                               │
│  ┌────────────────────┐                                      │
│  │   Editor Agent      │◄──── human conversation             │
│  └────────┬───────────┘                                      │
│           │ produces                                         │
│           ▼                                                  │
│  2. content/                       (prepared website assets) │
│  3. configuration.prompt.md        (build instructions)      │
│              │                                               │
│              ▼                                               │
│  ┌────────────────────┐                                      │
│  │  Publisher Agent     │  (no human interaction)            │
│  └────────┬───────────┘                                      │
│           │ produces                                         │
│           ▼                                                  │
│  4. _site/                         (rendered website)        │
│                                                              │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
│  Error feedback loop:                                        │
│  Publisher ──(issue)──► Editor ──(question)──► Human         │
│  Publisher ◄─(fix)───── Editor ◄─(answer)───── Human        │
└──────────────────────────────────────────────────────────────┘
```

### Step-by-step

1. **Human writes (or bootstraps) `description.prompt.md`** in the `_frontend-*/` workspace. This seed file states the website's purpose, lists candidate source files, and may include preferences about format or toolchain.

2. **Editor Agent session begins.** The Editor reads `description.prompt.md` and opens a conversation with the human to refine:
   - Which source files to include and how to organize them into sections.
   - Narrative framing, titles, and descriptions for each section.
   - Output format: Quarto website preset (`quarto create project website`), plain rendered Markdown, hand-coded HTML, or another option.
   - Any section-specific notes (e.g., "include only prints from `analysis/eda-1/prints/`").

3. **Editor produces `content/` and `configuration.prompt.md`.** The `content/` folder contains copies/transformations of source files, normalized for the chosen format. The `configuration.prompt.md` contains a deterministic, fully specified build plan.

4. **Publisher Agent executes.** It reads `configuration.prompt.md`, processes the `content/` folder, and produces `_site/`. The Publisher applies only simple, well-defined transformations (file placement, YAML generation, Quarto rendering, asset copying). It does **not** make editorial judgments.

5. **Error handling.** If the Publisher encounters an issue (missing asset, ambiguous instruction), it writes a structured error description. The Editor picks this up, interprets it, and asks the human for guidance. After resolution, the Editor updates `content/` or `configuration.prompt.md` and re-invokes the Publisher.

---

## Key Design Principles

1. **Separation of concerns.** Editorial complexity lives in one agent; rendering mechanics live in another. This keeps each agent simpler and more focused.

2. **One Editor, many Publishers.** The Editor is format-agnostic—it prepares content and a build plan. Different Publisher agents can target different rendering backends (Quarto, Hugo, plain HTML, PDF). Adding a new output format means writing a new Publisher, not rewriting the Editor.

3. **Publisher never talks to the human.** All human interaction flows through the Editor. This gives the human a single conversational partner and keeps the Publisher's behavior deterministic and testable.

4. **Content folder as contract.** The `content/` folder is the interface boundary between Editor and Publisher. Its structure and the accompanying `configuration.prompt.md` form a contract: the Publisher can rely on everything being present and correctly specified.

5. **Project-agnostic prompts.** The Editor and Publisher prompts should not hard-code project-specific vocabulary (e.g., "Ferry lane", "Ellis pattern"). Domain-specific context should come from the seed file (`description.prompt.md`) or from the repository's own documentation, not from the agent definitions themselves.

---

## Points of Confusion and Areas Needing More Specificity

The conversation establishes a clear high-level vision, but several details remain ambiguous or under-specified. These are flagged below for future resolution.

### 1. Exact schema of `configuration.prompt.md`

**What is clear:** The configuration file tells the Publisher what to build and in what order.

**What is unclear:** The precise format and required fields of this file. The current `_frontend-2/configuration.prompt.md` uses an informal Markdown structure (navbar sections, file globs, free-text notes). Questions that need answers:

- Is `configuration.prompt.md` a structured data format (YAML front matter + body) or free-form Markdown that the Publisher must interpret with natural language understanding?
- What fields are required vs. optional? (e.g., navbar structure, file list, section titles, per-file notes)
- How does the Publisher distinguish between "strict order of instructions" and the "short non-specific article" preamble that Sasha mentions?
- Should there be a formal schema or template that the Editor always produces, so the Publisher's parsing logic is deterministic?

**Recommendation:** Define a minimal schema (possibly YAML-based) for `configuration.prompt.md` to reduce ambiguity for the Publisher.

### 2. Structure and naming of the `content/` folder

**What is clear:** After the Editor session, a folder of prepared content exists in `_frontend-*/`.

**What is unclear:** The internal structure of this folder. Questions include:

- Is it always called `content/`, or can it vary?
- Does it mirror the website's section structure (e.g., `content/project/`, `content/analysis/`)?
- Does it contain copies of source files, or transformed/normalized versions?
- How are assets (images, CSS, data files) organized within it?
- If the chosen format is Quarto, does `content/` contain `.qmd` files, or does the Publisher generate `.qmd` wrappers around the Markdown?

**Recommendation:** Specify a default folder layout convention that the Editor follows, with documented variations per output format.

### 3. The `description.prompt.md` seed file

**What is clear:** A seed file exists that describes the website's purpose and candidate content.

**What is unclear:**

- Who writes this file—always the human, or can it be bootstrapped by another process?
- What level of detail does it require? (Compare the current `configuration.prompt.md`, which is about 30 lines, with Sasha's description of a more detailed file.)
- Is it consumed only by the Editor, or does the Publisher also read it?
- How does it relate to the current `configuration.prompt.md` in `_frontend-2/`? Is the current file playing the role of both seed and configuration?

**Recommendation:** Provide a template for `description.prompt.md` with labeled sections (purpose, candidate files, format preferences, constraints).

### 4. Error feedback loop mechanics

**What is clear:** The Publisher reports errors to the Editor, which relays them to the human.

**What is unclear:**

- How does the Publisher communicate errors? (A structured error file? A return code? A message in `configuration.prompt.md`?)
- Does the Editor re-invoke the Publisher automatically after fixing an issue, or does the human trigger a re-run?
- Is this a synchronous loop (Editor waits for Publisher) or asynchronous (separate sessions)?
- In the current Copilot agent framework, can one agent invoke another, or does the human mediate every handoff?

**Recommendation:** Document the error communication format and the expected handoff mechanism, accounting for the constraints of the GitHub Copilot agent platform.

### 5. Relationship between Editor output formats and Publisher variants

**What is clear:** Different Publishers handle different output formats (Quarto, plain HTML, etc.).

**What is unclear:**

- Does the Editor need to know which Publisher will be used, or does it produce a format-neutral `content/` folder that any Publisher can consume?
- If the Editor must tailor output to the Publisher, how does it know which Publisher is selected? (Is this specified in `description.prompt.md`?)
- Are Publisher agents expected to share a common interface (same `configuration.prompt.md` schema), or can each define its own?
- Sasha's description suggests the format choice happens during the Editor conversation ("just rendered md files, using quarto preset, or just vibecoding html simple website"). How does this choice propagate to the Publisher?

**Recommendation:** Decide whether `content/` is format-neutral (Publisher adapts) or format-specific (Editor adapts). If format-specific, the chosen format should be a mandatory field in `configuration.prompt.md`.

### 6. Scope of "simple modifications" by the Publisher

**What is clear:** The Publisher applies "simple modifications" as mentioned in the configuration.

**What is unclear:**

- What counts as a "simple modification"? (Frontmatter injection? Heading renaming? Image path rewriting? Content trimming?)
- Where is the line between an editorial change (Editor's job) and a rendering adjustment (Publisher's job)?
- Can the Publisher rewrite content to fit a template, or must it treat the content as read-only?

**Recommendation:** Define an explicit boundary: the Publisher may modify file structure and metadata (paths, YAML frontmatter, navigation wiring) but must not alter the substantive body content of any page.

### 7. Multiple `_frontend-*/` workspaces

**What is clear:** The naming convention `_frontend-*` allows multiple frontend workspaces (e.g., `_frontend-1/`, `_frontend-2/`).

**What is unclear:**

- When would a user create multiple workspaces? (Different audiences? Different formats? Iterations?)
- Is each workspace independent, or can they share a `content/` folder?
- Does each workspace get its own `description.prompt.md` and `configuration.prompt.md`?

**Recommendation:** Document the intended use case for multiple workspaces and whether they are independent or composable.

### 8. Project-specific vs. generic agent prompts

**What is clear:** The current `agent-presenter` prompts are too project-specific (they mention Ferry–Ellis–Mint architecture explicitly). These references should either be removed or generated dynamically.

**What is unclear:**

- Which parts of the current agent-presenter prompt should move into the Editor vs. remain in the Publisher?
- Should the Editor read project documentation (e.g., `ai/project/method.md`, `manipulation/pipeline.md`) to build context, or should that context be pre-loaded into `description.prompt.md`?
- How does the Editor avoid becoming project-specific itself?

**Recommendation:** The Editor prompt should be generic and obtain project context from the seed file and repository documentation at runtime. The Publisher prompt should reference only the `content/` folder and `configuration.prompt.md`, never repository-level project documentation.

---

## Summary

The two-agent architecture separates **what to publish** (Editor) from **how to render it** (Publisher). The Editor is a single, reusable conversational agent that helps humans make editorial decisions and produces a standardized content package. The Publisher is a simpler, format-specific agent that deterministically renders the content package into a website. This separation enables multiple output formats without duplicating editorial logic and keeps each agent focused on a well-defined task.

The primary work remaining is to define the contracts between the agents—specifically the structure of `description.prompt.md`, the schema of `configuration.prompt.md`, the layout of the `content/` folder, and the error feedback protocol.
