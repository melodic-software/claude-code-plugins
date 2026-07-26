# PLAN — skill-cheat-sheet (#1227)

## Brief

### TLDR

Generate a consumer-neutral, scan-and-go skill-selection cheat sheet at `docs/SKILL-CHEAT-SHEET.md`,
grouped by the session-flow workflow's own stage vocabulary, derived from new official
`metadata` frontmatter keys in each in-scope `SKILL.md`, drift-gated in CI — then split the
top-level README into a small entry point (phase 2). Issue: #1227.

### Goal

1. **Cheat sheet (phase 1).** A generated markdown page mapping "type of thing I'm doing" to
   the skill to invoke, covering the full dev lifecycle from "I don't know what I'm going to
   build" through discovery, research, planning, implementation, testing, review, verification,
   PR, and merge — plus an anytime/cross-cutting group (discipline correctors, re-anchoring,
   docs-hygiene, naming, visualization, education) and a session-lifecycle group, and an
   org-agnostic operator-cadence section (daily/weekly fleet rhythm). Every dev-lifecycle-relevant
   skill is included; no relevant skill left out.
2. **README split (phase 2).** Shrink `README.md` to a small entry point; push detail into
   linked pages; the cheat sheet is the primary "which skill?" destination. The generated
   catalog block's new home is decided here, and `scripts/generate-catalog.mjs`'s output path is
   parameterized accordingly.

### Constraints

Locked upstream (issue #1227 — not re-litigable):

- Auto-derived from `SKILL.md` frontmatter; only a thin hand-curated grouping layer (stage order
  + group labels) is hand-maintained. Zero duplicated per-skill detail.
- CI drift check between the generated sheet and its frontmatter sources.
- Markdown canonical; any HTML rendering generated from it.
- Minimal per-skill detail: what/when one-liner + link. Clickable TOC on GitHub.

Locked this interview (validated by two independent fresh-context reviewers; evidence verified):

- **Data mechanism:** per-skill keys under the Agent Skills standard `metadata` frontmatter
  field — flat string→string, namespaced (shape precedent: `discipline-batch` keys), e.g.
  summary (hard cap ~100 chars, gated by skill-quality), stage, cadence, include/exclude.
  The `description` field CANNOT source the one-liner (median 577 chars; first-sentence median
  188; shortening blocked by the trigger-keyword-preservation check). Key vocabulary lands as
  part of the fleet-wide effort #1617 (this work is its first consumer).
- **Grouping spine:** the session-flow workflow stage vocabulary VERBATIM —
  `0. Contract` through `8. Retrospective` plus `PR lifecycle (after step 7)` (see
  `plugins/session-flow/skills/workflow/context/steps.md`) — plus the two new groups
  (anytime/cross-cutting, session lifecycle) and the operator-cadence section. Sequence-of-use
  is a distinct axis from `docs/CATALOG-TAXONOMY.md`; a short ownership note states both axes.
- **Audience:** consumer-neutral. Rows grouped by plugin within each stage with the install
  identifier visible, so a partial-install consumer can act on the page. Operator section framed
  as "how an operator runs this fleet", never owner-specific.
- **Generator:** new sibling script beside `scripts/generate-catalog.mjs`, sharing the
  marker-block + `--check` idiom; output paths parameterized in BOTH generators. `--check`
  wired into `scripts/validate-plugins.sh`. Generator fails on any unmapped in-scope skill and
  any orphaned mapping; exclusions are explicit entries. Emits an anchor-linked group TOC.
  Emits links only to paths it read from disk (offline lychee gate).
- **Location hazard:** the sheet lives at `docs/SKILL-CHEAT-SHEET.md` — NOT under
  `docs/topics/` (sole prefix in `scripts/docs-only-paths.txt`; placing it there would skip its
  own drift gate). Update the lane comment in `docs-only-paths.txt` and the pinning case in
  `scripts/check-docs-only.test.sh` when wiring CI.
- **Blast radius:** frontmatter sweep touches every in-scope `SKILL.md` (~183 skills across 61
  plugins) → `work-class: structural`. Version-bump/changelog posture for the sweep is decided
  at planning before the sweep starts.

### Acceptance criteria

- `docs/SKILL-CHEAT-SHEET.md` exists, generated, with: stage-grouped skill rows (one-liner +
  link + install identifier per plugin group), anytime + session-lifecycle groups, operator-
  cadence section, anchor-linked TOC; renders scannably on GitHub.
- Every dev-lifecycle-relevant skill appears exactly once in a stage or group; exclusions
  (infra hooks, setup skills, maintainer-only, personal-domain plugins) are explicit generator
  entries, not silent omissions.
- CI fails when frontmatter and sheet diverge, when an in-scope skill lacks mapping metadata,
  or when a mapping references a missing skill.
- Phase 2: README reduced to a small entry point whose links reach everything it previously
  contained; catalog generator still green at its new target.
- All existing gates green (validate-plugins, markdownlint, lychee, docs-only lane tests).

### Captured assumptions

- Fleet-wide metadata vocabulary (#1617) may land after this; the `cheatsheet-*` keys adopted
  here migrate into that vocabulary rather than beside it.
- Claude Code ignores unknown/spec-standard frontmatter fields (verified against current docs +
  in-repo production usage of `metadata`).

### Out-of-scope

- Standalone agent rows (9 agents) — deferred with trigger: when agents gain an equivalent
  metadata block (see #1617). Agent-invoking skills ARE on the sheet.
- Hook plugins as rows (not invoked), personal-domain plugins (songwriting, kindle-dedrm, x,
  ai-briefing, knowledge, machine-health).
- HTML rendering surface (later, generated from markdown only).
- Fleet-wide metadata classification beyond the cheat sheet's own keys (#1617).

### Deferred questions

- Exact `cheatsheet-*` key names and value enums — arbiter: `/planning:plan` (coordinate with
  #1617's naming guidance; flat string values per spec).
- Version-bump/changelog posture for the ~61-plugin frontmatter sweep (single fleet PR vs
  per-plugin) — arbiter: `/planning:plan`.
- Which README sections move where in phase 2, and the catalog block's new home — arbiter:
  `/planning:plan`.
- Whether operator-cadence rows also carry `status`/frequency detail beyond daily/weekly —
  arbiter: `/planning:plan`.

## Plan

(To be filled by /planning:plan.)
