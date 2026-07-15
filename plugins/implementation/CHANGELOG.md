# Changelog

All notable changes to the `implementation` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.1]

### Fixed

- **`/implementation:setup` reports `vault_backend: gitbook` as deferred and non-writable.** Offering
  or preserving the key now cites the ADR
  (`docs/adr/0001-defer-gitbook-as-knowledge-vault-backend.md`) and states that durable writes still
  target `docs`; the skill never configures or tests a GitBook API, MCP, or Git Sync writer.

## [0.5.0]

### Added

- **Optional `tool-pin` version-drift warning in `/lint`.** The ecosystem-commands contract gains an
  optional `tool-pin` key (pinned tool versions keyed by tool name; contract 1.1.0): when the resolved
  config pins a tool version, `/lint` warns if the installed version drifts from the pin (a pin
  typically mirrors the consumer's own CI pin). Inert when absent — no pin, no check.
- **`/implement` over-correction trap logs to the session retro.** When the Step 3.5 over-correction
  guard fires, document it in the session's retro — surfaced to `/session-flow:retro` when the
  `session-flow` plugin is installed; otherwise noted in the completion summary.

## [0.4.0]

### Changed

- **Consume the topic-docs convention** (`docs/conventions/topic-docs/README.md`). Artifact placement
  follows document nature across two tiers, bound for this plugin in the shared
  `reference/topic-docs.md`: `PLAN.md` progress marks and the `DEVIATIONS.md` log are contract-tier
  (`docs/topics/<slug>/`, committed on the task branch, pruned before merge — or the memory tier under
  `contract_tier: local`); baselines, raw captures, and the status summary are memory-tier
  (self-ignoring `.work/<slug>/`); fallback handoff notes land in the memory tier's `.work/handoffs/`
  home owned by `session-flow`. Placement resolves through the contract's resolution order (concern
  file `.claude/topic-docs.yaml` first) with its runtime guards: `git check-ignore` on the session's
  first contract-slice write, and a first-per-session self-ignore check scoped to the resolved memory
  root; no edits to the consumer's root `.gitignore`.
- **`/implement` Step 4 phase commits carry plan + source together.** With the plan tracked on the
  task branch, "commit the plan changes alongside the phase's source-code changes in a single commit"
  is now literal git behavior — one commit, one story; memory-tier files never enter the commit.
- **`/verify-changes` evidence directory renamed `verify/` → `verification/`.** The distilled,
  `verified_at_sha`-keyed manifest is contract-tier at `docs/topics/<slug>/verification/` and meets
  the contract's redaction bar (no raw captures, machine-local paths, usernames, or credentials);
  raw captures stay in `.work/<slug>/scratch/`. The skill's evals assert the migrated locations.
- **`/verify-improvement` baselines are memory-tier** at `.work/<slug>/baselines/` — machine-bound
  measurements, never committed, no longer beside the plan artifact (contract-tier at
  `docs/topics/<slug>/PLAN.md`); the comparison summary surfaces in the plan and the PR body.

### Added

- **`reference/topic-docs.md`** — the plugin's **deltas-only** binding to the topic-docs contract:
  its per-artifact tier table and the `DEVIATIONS.md` pin and phase-commit rule — the contract owns
  the resolution order, slug spec, and runtime guards. All consuming skills reference this one
  document.
- **`/implementation:setup` offers the `.claude/topic-docs.yaml` concern file** — one question
  (`contract_tier: branch` recommended), offering and preserving every schema key (`contract_dir`,
  `memory_dir`, `contract_tier`, `vault_backend`), conflict-checked with `git check-ignore -v` on
  the chosen contract root before writing — only when the chosen tier is `branch` (local mode has
  no committed tier to guard); never edits the consumer's root `.gitignore`.

### Removed

- **`notes_dir` userConfig option and the `.claude/notes/<slug>/` layout.** Retired outright — no
  compatibility layer, no dual-read window, no migration tooling; move residual content manually.

## [0.3.0]

### Added

- **Rich-form evals for five skills.** `evals/evals.json` ships for `implement`, `implement-dispatch`,
  `build`, `lint`, and `setup` — the skills' judgment-bearing contracts (mode/orchestration routing,
  divergence and scope-fence guardrails, skip-not-FAIL and consumer-config-precedence behavior, and the
  config-writer's interview/write-scope discipline) are now covered by objectively-verifiable cases,
  modeled on the `bug-report` rich-form exemplar and validated against
  `plugins/skill-quality/reference/evals.schema.json`. Evals are a shipped component, so this minor bump
  is their delivery vehicle; no behavioral change to the skills themselves.

## [0.2.0]

### Changed

- **Consume the ecosystem-commands contract.** The two divergent per-ecosystem reference tables
  (`skills/build/reference/ecosystem-config.md` and `skills/lint/reference/ecosystem-config.md`) are
  replaced by ONE bundled, schema-conformant set of portable-default files at
  `reference/ecosystems/<ecosystem>.yaml`, validated against the contract's `ecosystem.schema.json`
  (`docs/conventions/ecosystem-commands/README.md`). Both `/build` and `/lint` now read the one
  location.
- **Ladder resolution in `/build` and `/lint`.** Each ecosystem's command surface resolves through the
  contract's four-rung ladder (shared doc: `reference/resolution-ladder.md`): consumer
  `.claude/ecosystems/<ecosystem>.yaml` (additive over a `~/.claude/ecosystems/` user-global base and a
  `.local.yaml` overlay) → inference → ask → bundled portable defaults. A malformed consumer file warns
  and degrades to inference, never a hard stop. Bundled defaults are the rung-4 fallback only, never
  written into a consumer repo outside setup or a persisted inference.
- **Unified command keys.** The old build-table `lint-cmd` and lint-table `check-cmd` were the same
  verb; they collapse to the contract's `check-cmd`. Command keys are now `build-cmd`, `test-cmd`,
  `check-cmd`, `fix-cmd`.

### Added

- **`/implementation:setup`** — re-runnable skill that interviews, infers, and writes the consuming
  repo's tracked `.claude/ecosystems/*.yaml`, the ladder's writer for the infer/ask rungs.

### Design decisions (from the wave-2 design gate; recorded, not reopened)

- **Data unified, scope preserved.** Unifying the tables into one 8-ecosystem set would have pulled the
  lint-only `yaml` and `cross-cutting` surfaces into `/build` — and `cross-cutting`'s `**` glob matches
  every change. Per the contract's canonical-verb-vs-context-binding split, the *data* is unified while
  each skill keeps its *scope* (binding is per-surface): `/build` covers
  dotnet/python/typescript/bash/powershell/markdown; `yaml` and `cross-cutting` remain `/lint`-only.
- **Reconciled divergences.** Where the two old tables disagreed, the contract's worked examples are the
  authority: dropped the lint-table's `$REPO_ROOT/`-prefixed dotnet command in favor of the contract's
  `<solution-or-project-file>` form (the running skill resolves absolute paths).
- **Config home is concern-named** `.claude/ecosystems/` (a recorded precedent-extension of the
  extensibility-contract seam, since more than one plugin consumes it). No new `userConfig` knob — the
  path is conventional, not declared. Task-runner deferred — command values stay opaque strings.

## [0.1.0]

- Initial release: ten skills — `implement`, `implement-dispatch`, `build`, `lint`, `test-write`,
  `test-plan`, `test-diagnose`, `test-e2e`, `verify-changes`, `verify-improvement`.
