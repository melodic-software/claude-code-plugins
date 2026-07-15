# Changelog

All notable changes to the `planning` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.9.1]

### Fixed

- **GitBook remains non-writable throughout planning close-out**: `/planning:architect` and the
  topic-docs binding now route `vault_backend: gitbook` to the in-repo `docs` promotion path without
  invoking GitBook API/MCP or Git Sync writes. `/planning:setup` preserves an existing key while
  reporting its deferred, non-writable status instead of implying that it enables a writer.

## [0.9.0]

### Added

- **Agent-team composition guidance in `/planning:architect` Step 4.5**: design for an agent team
  when parallel-safe workers must message each other (vs independent fan-out sub-agents);
  decompose by context boundary / disjoint clean-interface file-set, never by lifecycle role;
  dependency-order the task list so blocked tasks auto-unblock; teammates are not
  worktree-isolated, so disjoint file ownership is mandatory. The Step 4.5 routing enum regains
  the agent-team surface.

### Changed

- **Baseline capture routes to the measurement SSOT**: `/planning:architect` Step 2 routes to
  `/implementation:verify-improvement` (`performance baseline` / `metrics baseline`) when
  installed instead of restating the measure/store/compare mechanism inline; manual capture
  remains the degrade path.
- **`/planning:devils-advocate` follow-ups regain the verification pointer**: suggests
  `/implementation:verify-changes` (if installed) when code changes were involved.

## [0.8.0]

### Changed

- **Migrate to the topic-docs convention** (`docs/conventions/topic-docs/`, v1.0.0). Artifacts now
  split by document nature across two tiers sharing one topic slug: contract documents — `PRD.md`,
  `PLAN.md` (Brief + Plan), and ALL of `design/` including the `design-threads.md` /
  `design-resolution.md` gate files — land in `docs/topics/<topic-slug>/`, committed on the task
  branch and pruned before merge; working memory — `interview-checklist.md`,
  `architect-checklist.md`, `baselines/`, resume notes — lands in the never-committed,
  self-ignoring `.work/<topic-slug>/`. `contract_tier: local` keeps contract kinds in the memory
  tier for solo/offline work. Every pipeline skill resolves placement by citing the plugin's
  **deltas-only** binding `reference/topic-docs.md` — its artifact/tier table and the vault-seam
  close-out pointer; the contract owns the resolution order, slug spec, and runtime guards
  (self-ignore is verified on the session's first memory-tier write, scoped to the resolved
  memory root).
- **`/planning:setup` now writes the tracked concern file** `.claude/topic-docs.yaml`
  (offering and preserving every schema key — `contract_dir`, `memory_dir`, `contract_tier`,
  `vault_backend`; shape per the convention's `topic-docs.schema.json`) instead of the
  `notes_dir` userConfig. It runs the committed-tier `git check-ignore -v` conflict check before
  writing — only when the chosen tier is `branch` (local mode has no committed tier to guard) —
  and never edits the consumer's root `.gitignore`.
- **`/planning:architect` owns the contract-slice close-out**: at PR time the approved PLAN.md is
  pasted into the PR description inside a `<details>` block; durable outcomes graduate through the
  knowledge-vault seam by resolving the concern file's `vault_backend` (`docs` default: guarded,
  history-preserving `git mv` into `docs/adr/` / `docs/specs/`; other values name a
  consumer-documented backend, degrading to `docs` when its tools are absent); a final commit
  prunes `docs/topics/<topic-slug>/` leaving context pointers.
- **Baselines are memory-tier**: the architect's baseline-capture step stores raw, machine-bound
  captures under `.work/<topic-slug>/baselines/`; PLAN.md records the distilled baseline, target,
  and comparison — never the raw output.
- **`/planning:brainstorm` opt-in persistence** targets the memory tier
  (`.work/<topic-slug>/brainstorm.md`), never the contract slice.
- **`/planning:wayfind`** cites the convention's memory tier and slug spec for its
  `.work/<slug>/` execution artifacts (alignment only — the map stays tracker-native).

### Removed

- **`history.md`** — every instruction that appended dated scope-change / pivot / restart notes to
  a sibling `history.md` is gone. Scope changes now append a dated note to the relevant section of
  the artifact itself, and the commit message carries the pivot rationale — contracts are
  branch-tracked, so git log is the history.

- **`notes_dir` userConfig and the `.claude/notes/` layout** — retired outright. No compatibility
  layer, no dual-read window, no migration tooling; move residual content manually.
