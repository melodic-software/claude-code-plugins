# Changelog

All notable changes to the `planning` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
  **deltas-only** binding `reference/topic-docs.md` — its artifact/tier table, the grace
  algorithm's parameters (slice axis: topic slug; legacy root: `.claude/notes/` or a set
  `notes_dir`), the vault-seam close-out pointer, and the one guarded migration command; the
  contract owns the resolution order, slug spec, and runtime guards (self-ignore is verified on
  the session's first memory-tier write, scoped to the resolved memory root).
- **`/planning:setup` now writes the tracked concern file** `.claude/topic-docs.yaml`
  (offering and preserving every schema key — `contract_dir`, `memory_dir`, `contract_tier`,
  `vault_backend`; shape per the convention's `topic-docs.schema.json`) instead of the
  `notes_dir` userConfig. It runs the committed-tier `git check-ignore -v` conflict check before
  writing, never edits the consumer's root `.gitignore`, and its guarded migration completes only
  when the `notes_dir` key is removed from every settings scope that sets it.
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

### Deprecated

- **`notes_dir` userConfig** — grace path only: when set ("set" is decidable — the key present
  with any value, or the legacy root holding topic content), skills operate wholly on the old
  location (reads AND writes) and emit a deprecation notice; never dual-write, never split one
  topic across roots. Removed at the next major version.
