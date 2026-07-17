# Changelog

All notable changes to the `planning` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.13.0]

### Changed

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` records that
  baselines are checkout-local and `PLAN.md` carries distilled values only;
  `/planning:architect`'s baseline step no longer directs `PLAN.md` to reference the stored
  memory-slice capture (pointer discipline — the path is invisible outside the writing checkout).

## [0.12.0]

### Changed

- **`/planning:wayfind` label taxonomy follows the colon-space axis grammar**: the typed decision-item
  labels are now `wayfind: research|interview|design|prototype|task` (previously `wayfind:research`
  etc.), so label-as-code owners with a `prefix: value` naming grammar can declare the taxonomy
  verbatim instead of carrying a grammar exception. `work-map` and `needs-human` stay flat
  (grammar-exempt). Frontier queries and the bootstrap presence check match the new names. Maps
  charted under the old names need a one-time label rename before `work` mode can route them.

## [0.11.1]

### Fixed

- **GitBook remains non-writable throughout planning close-out**: `/planning:architect` and the
  topic-docs binding now route `vault_backend: gitbook` to the in-repo `docs` promotion path without
  invoking GitBook API/MCP or Git Sync writes. `/planning:setup` reports the deferred, non-writable
  status whenever the effective value is `gitbook` — preserved from an existing file, inferred from
  the repo's own conventions, or chosen during the interview — instead of implying that any of those
  paths enables a writer.
- **`/planning:architect` Action Router recognizes `close-out`**: the PR-time close-out procedure was
  documented but unreachable through the router, so `close-out` fell through to full planning instead
  of running the close-out steps. The router now routes it directly, and the eval that exercises the
  GitBook-deferral close-out path is reachable again.

## [0.11.0]

### Added

- Added `/planning:domain-modeling`, the active owner for committed project-glossary changes:
  discovery-first consumer format/location resolution, canonical terms plus rejected synonyms,
  tight what-it-IS definitions, purity/admission guards, and routing among already-known bounded
  contexts. It deliberately does not discover bounded contexts or create speculative empty files.

### Changed

- `/planning:interview` and `/planning:design` now invoke the domain-modeling owner when vocabulary
  resolves instead of maintaining parallel glossary disciplines.

## [0.10.1]

### Changed

- Synced sibling-skill invocation routes to the reorganized plugin taxonomy across
  `architect`, `brainstorm`, and `devils-advocate`: `/tdd:tdd` is now
  `/tdd:principles`; `/implementation:verify-improvement` is now
  `/verification:measure`; `/implementation:verify-changes` is now
  `/verification:confirm`; `/improve-architecture:improve-architecture` is now
  `/architecture:improve`; `/work-items:work-items` is now `/work-items:track`.

## [0.10.0]

### Added

- **ADR admission test at `/planning:architect` close-out**: a decision graduates as an ADR only
  when ALL three hold — hard to reverse, surprising without context, the result of a real
  trade-off; ADRs stay minimal (title + a few sentences, optional sections only when they earn
  their place), and the ADR is preferably written the moment the decision crystallizes rather
  than batched at graduation.
- **Durability-over-precision authoring rule in `/planning:prd`**: PRD content describes
  interfaces, types, and behavioural contracts — never file paths or line numbers — and never
  assumes the current implementation structure persists.
- **Test-seam posture thread in `/planning:design` Phase 2**: sketch the seams the feature will
  be tested at — prefer existing seams, place new ones as high as possible, drive toward the
  fewest (ideal: one) — and confirm the sketch with the user before design output is finalized.
  `/planning:prd` gains a one-line pointer routing test-seam sketching to `/planning:design`.
- **Non-goals graduation edge in `/planning:prd`**: a permanent, deliberate rejection (not a
  deferral) graduates to the consuming repo's rejected-concept ledger at
  `docs/out-of-scope/<concept>.md` — one file per concept, accreting a "Prior requests" log — so
  repeat proposals get answered by the ledger; consumer convention with graceful degrade (create
  lazily; plain Non-goals suffice when no ledger exists).
- **Committed project-glossary format** (`skills/design/context/project-glossary.md`): one term
  per entry, 1–2 sentence what-it-IS definition, an `Avoid:` line pinning rejected synonyms,
  project-context terms only, lazy creation at the repo root (or per-context with a root map
  file), updated the moment a term resolves. `/planning:design`'s type-modeling and terminology
  guidance now writes through it.
- **Re-read-before-write discipline for multi-turn shared artifacts**: `/planning:architect`
  (PLAN.md) and `/planning:design` (design-threads.md and peers) re-read the artifact from disk
  before every write — another turn or agent may have modified it — and prefer appending or
  refining over wholesale rewrites.

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
