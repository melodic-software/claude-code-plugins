# Underspecification — planning-pipeline vocabulary

## Brief

### TLDR

- Name "underspecification" as first-class vocabulary in existing planning skills — no new skill, no new reference doc.
- Add "underspecification"/"underspecified" to `/planning:interview` trigger keywords and Purpose framing (the skill is the pipeline's underspecification resolver).
- Add one-line concept mentions only where skills already cover it: `/planning:prd` (ambiguity routing), `/planning:design` (underspecified types); `/planning:wayfind` only if its text confirms fit.
- Vocabulary/routing change only — no capability change.

### Goal

The concept the planning pipeline exists to resolve — a task or prompt missing the constraints needed to act on it safely — is never named in the repo, so the term neither triggers the right skill nor appears in skill framing when users or agents reach for it. Outcome: "underspecification" routes to `/planning:interview` and is named in the skills that already embody the concept.

### Constraints

- No new skill and no new reference doc (alternatives explicitly declined).
- Fresh-docs mandate (repo `CLAUDE.md`): WebFetch the current skills/plugins doc pages before editing and cite URLs.
- `/skill-quality:check` gate governs edits: description listing-budget cap and trigger-keyword preservation.
- No academic content copied into the repo; term naming only, citations stay out.
- PR required; squash merge; Conventional Commits title; branch `<type>/<description>`.

### Acceptance criteria

- "underspecification" (and/or "underspecified") present in `/planning:interview` frontmatter description trigger keywords and Purpose section.
- Concept mentions added only in skills that already cover it; no scope creep into unrelated skills.
- `/skill-quality:check` passes for every touched skill.
- No new files under `plugins/planning`.

### Captured assumptions

- Importing the academic term into practitioner-facing skill docs is worthwhile despite thin practitioner usage (it is the precise name for what the pipeline resolves) — revisit if the term confuses consumers or practitioner usage never materializes.
- Trigger coverage of "underspecified"/"underspecification" suffices; hyphenated "under-specified" not needed — revisit if doc search shows the hyphenated form in the wild.

### Out-of-scope

- Any new spec-driven-development skill — external research (2026-07-19) found the pipeline already sits inside SDD's surviving human-gated mainstream; no capability gap.
- In-repo definition/citation reference doc for the term.
- `plugins/playbooks/fable-5` wording ("under-specifies") — left as-is.

### Deferred questions

- Include `/planning:wayfind` in the edit set? — defer until implementation reads its SKILL.md; **arbiter: /architect**
- Exact keyword placement within each description's listing budget — defer to implementation; **arbiter: /architect**

## Plan

<!-- populated by /architect -->
