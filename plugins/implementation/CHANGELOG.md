# Changelog

All notable changes to the `implementation` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.7.8]

### Changed

- `implement-dispatch`'s fresh-context verifier before marking a phase `[DONE]` (`skills/implement-dispatch/SKILL.md`)
  now prefers a cross-vendor advisor when one is installed (e.g. the OpenAI Codex plugin's `/codex:review` or
  `/codex:adversarial-review`), with the fresh-context same-vendor verifier sub-agent as the stated fallback —
  presence-gated per the seam-phrasing convention.

## [0.7.7]

### Changed

- `implement-dispatch`'s "Compose the brief" step (`skills/implement-dispatch/SKILL.md`) now front-loads
  CI-hygiene and early-push clauses alongside the existing worktree-cwd clause: no issue-number back-references
  in code comments (the `comment-hygiene` check flags them; `TODO(#issue)` is the sanctioned exception);
  any new regular file with a shebang (never a `120000` symlink — `git update-index --chmod=+x` fails on
  one) must be marked executable on both the worktree and the index, in order — `chmod +x <path>`, then
  `git add <path>` to stage it (a not-yet-tracked path fails `git update-index --chmod=+x` outright), then
  `git update-index --chmod=+x <path>` to force the index mode explicitly, since a plain `git add` alone
  can't be trusted to carry an executable bit across every platform/filesystem (the `exec-bit` check flags
  a tracked shebang file recorded non-executable); and commit and push as early as practical — before the
  CI-poll tail — so a mid-flight worker session-limit death never orphans unpushed work. That early commit
  is a source-only checkpoint; the phase-boundary plan-mark commit (`/implementation:implement` Step 4 item
  4) still runs separately, orchestrator-side, once the phase's acceptance criteria are verified — a scoped
  exception to inline mode's combined source+marks commit, noted in "Phase boundaries." PR creation stays
  out of every worker brief; it belongs to the orchestrator's post-verification flow (Step 5), invoked only
  after every worker return is verified and the build/test gate passes. Reinforced as Gotchas-section
  reminders, matching the worktree-cwd clause's existing pattern. Closes #819, where fresh dispatched
  workers repeatedly learned these same PR-contract constraints via red CI instead of the brief.

## [0.7.6]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.7.5]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.7.4]

### Changed

- `implement-dispatch`'s "Compose the brief" step (`skills/implement-dispatch/SKILL.md`) now requires
  a worktree-cwd clause whenever a worker edits in a dedicated worktree: the brief must give the
  worktree's absolute path and instruct the worker to never rely on the shell's working directory
  persisting across separate tool calls — anchoring every command that touches the worktree (file
  edits and git operations alike: `status`, `add`, `commit`, `diff`, `log`) with
  `git -C <worktree-path>` (or a re-`cd` per call) rather than a one-time `cd`, since cwd can drift
  between a read and the next write and silently risks committing into the wrong checkout. Reinforced
  as a Gotchas-section reminder. Closes the correctness gap behind #566, where a dispatched worker's
  edits landed in the canonical checkout instead of its assigned out-of-tree worktree.

## [0.7.3]

### Changed

- Stack-qualified the `implement` skill's optional-collaborator references: the mode contexts
  (`skills/implement/context/feature.md`, `bugfix.md`, `refactor.md`) retain their `dotnet-*`
  marketplace-skill names and `## Marketplace plugin skills (invoke only when installed)` presence
  gate, and each now opens with a lead-in that frames those skills as .NET-ecosystem forward
  references — invoked only when your stack is .NET and the plugin is installed — with an explicit
  fallback to the project's own tooling otherwise, so a non-.NET consumer keeps the generic path
  first-class rather than being handed a dead list. Matches the conforming `testing` (#491) and
  `verification` (#526) pattern per the ratified #412 disposition governing #405. No reference
  removal; every reference stays optional and installed-gated.

## [0.7.2]

### Changed

- Layer-vocabulary agnosticism: the `implement` skill's cross-layer guidance
  (`skills/implement/SKILL.md` "Dependency direction" and
  `skills/implement/context/feature.md` step 3) no longer bakes the .NET/Clean-Architecture
  layer names (Core/Domain/Application/Infrastructure) as a universal execution order. The
  principle is restated as dependency direction — implement depended-upon components before
  their dependents, respecting the project's own dependency direction — and the layer names
  are demoted to a clearly-marked ".NET, for example" illustration, per the
  `docs/PLUGIN-PHILOSOPHY.md` design boundary.

## [0.7.1]

### Fixed

- Branch-naming grammar in `/implementation:implement` Step 1 and its gotchas no longer presents
  `<type>/<description>` as the mandated form; it now defers to the consuming project's branch-naming
  convention (its `CLAUDE.md` / `AGENTS.md` / rules) and frames `<type>/<description>` as a common default, mirroring
  the commit-message convention deferral. The branch-check eval is reframed to accept any convention-
  compliant branch name rather than a single hardcoded grammar.

## [0.7.0]

### Changed

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` ties the
  phase-commit rule to the contract's visibility guarantee — isolated contexts see the contract
  slice as committed state only — and states the by-value return rule for dispatched workers.

## [0.6.2]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

## [0.6.1]

### Changed

- References to the renamed `/toolchain:build` skill now invoke `/toolchain:check` (toolchain 0.2.0 breaking rename). Version bumped so existing installs pick up the rewritten prompts.

## [0.6.0]

### Changed — nine skills extracted into three new plugins (migration required to retain them)

**The `implementation` plugin is now two skills — `/implementation:implement` and
`/implementation:implement-dispatch`.** The other nine skills moved out into three new plugins.
Consumers who relied on any moved skill MUST install the new plugin that now owns it to keep the
capability — there is no renames-map path for extracted skills:

- **`build`, `lint`, `setup` → the new `toolchain` plugin** (skill names unchanged):
  `/toolchain:build`, `/toolchain:lint`, `/toolchain:setup`. The `reference/resolution-ladder.md` and
  the `reference/ecosystems/` portable defaults moved with them.
- **`test-plan`, `test-write`, `test-e2e`, `test-diagnose` → the new `testing` plugin, renamed:**
  `/testing:plan`, `/testing:write`, `/testing:e2e`, `/testing:diagnose`.
- **`verify-changes`, `verify-improvement` → the new `verification` plugin, renamed:**
  `/verification:confirm`, `/verification:measure`.

This split is **presence-gated graceful degradation, NOT a hard dependency.**
`/implementation:implement` and `/implementation:implement-dispatch` still run their cadence when a
companion plugin is absent — they fall back to the project's own build/test command and to self-verifying
the outcome against the plan/intent — and prefer the companion skill (`/toolchain:build`,
`/verification:confirm`, `/testing:*`) when it is installed. To restore the full former surface, install
`toolchain`, `testing`, and/or `verification`.

### Changed

- **Seam references rewritten to the new namespaces and presence-gated.** Every in-skill reference to a
  moved skill now names its new plugin (`/toolchain:*`, `/testing:*`, `/verification:*`); active
  invocations are gated with a graceful fallback, and relationship prose that called the moved skills
  "siblings" is reframed to "companion skills in separate plugins."
- **`reference/topic-docs.md` trimmed** to the artifacts these two skills write — `PLAN.md` progress
  marks, the `DEVIATIONS.md` log, the status summary, and handoff notes. Verification manifests and
  baselines are now the `verification` plugin's, bound in its own `reference/topic-docs.md`.

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
