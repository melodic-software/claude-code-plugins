# Changelog

All notable changes to the `claude-config` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.10.0]

### Added

- **`audit-instructions` checks I12–I14**, extending the existing `reference/criteria.md` catalog
  rather than standing up a second one. I12 flags an instruction asserting a Claude Code *harness*
  behavior that the current official page contradicts — the product, not the model, which is what
  separates it from I8. I13 flags an `@path` written where `@` carries no import meaning, so the
  cited content silently never arrives. I14 flags an instruction telling a subagent to read a
  surface the main conversation loads at startup and therefore already carries. Each row carries its
  must-not-flag cases, and the three new official sources (CLI reference, subagents, skills) join the
  catalog's source list.

### Changed

- **Recheck triggers now watch every page in the catalog's source list**, not the three originally
  named. Each check cites one of those pages, so a subset left the new harness-behavior rows
  depending on pages nothing watched.
- **I12 no longer treats documentation silence as drift.** Detection now requires an official page
  stating something incompatible with the claim, or a failed version-matched reproduction. A page
  that stops mentioning a behavior is not evidence the behavior changed — pages are routinely
  rewritten and condensed, and this repository keeps empirical tests for behaviors the docs never
  specified at all.
- **I14 is bounded to the surfaces actually loaded at startup.** The subagent guarantee it rests on
  covers the hierarchy *the main conversation loads*; nested `CLAUDE.md` files and path-scoped rules
  load lazily when work reaches their scope, so an instruction to read a package-local file before
  operating there can be doing real work. Flagging it would have removed scoped instructions.

- **`Authority` gloss restated descriptively.** It now reads "All fourteen checks are currently
  `ANTHROPIC-DOCS`" — a statement about the catalog's present contents, not a rule. `TALK` and
  `OPINION` stay reachable for a future row, and the axis stays a closed three-value set rather than
  widening under every existing consumer.

## [0.9.2]

### Changed

- Fresh-eyes delegation sites now prefer a cross-vendor advisor when one is installed
  (e.g. the OpenAI Codex plugin, invoked per its own docs), with the fresh-context same-vendor
  subagent as the stated fallback — presence-gated per the seam-phrasing convention.

## [0.9.1]

### Added

- **`audit-instructions` eval: `step-list-culled-not-preserved`.** Exercises check I8's
  step-list nuance: a mechanical numbered procedure is culled to intent plus hard constraints
  (genuine ordering, safety gates, external contracts kept) rather than preserved verbatim.
  Absorbed from the superseded `audit-model-fit` suite (its C2 analog), per the follow-up
  material recorded when 0.9.0 removed that skill.

## [0.9.0]

### Added

- **`audit-instructions` skill** (`/claude-config:audit-instructions`). A read-only audit of the
  locally-owned Claude Code instruction surfaces — user + project `CLAUDE.md`, `.claude/rules`,
  skill bodies, agent definitions, prompt-type hooks, output styles — for instructions current
  models no longer need: prior-model workarounds, over-prescriptive scaffolding, bare prohibitions,
  reasoning-echo directives, and approach-pinning example blocks. It ships an eleven-check catalog
  (`reference/criteria.md`) cited to current official prompting doctrine, tiers every finding
  mechanical vs behavioral, and packages proposed removals/rewrites as human-gated diffs — never
  auto-applied. An advisory grep-only scanner (`scripts/instruction-scan.sh`) seeds the mechanical
  tier. It partitions with `claude-memory`'s `audit` skill: on memory-layer surfaces it runs only
  the model-era checks and routes hygiene findings there; on non-memory surfaces the full catalog
  applies. Upstream-owned plugin-cache and managed-materialization findings route to the owning
  repository rather than being edited in place.

### Fixed

- Corrected stale `claude-memory` skill-name references (`health` → its current name `audit`)
  across the plugin's skills and README — the `audit`, `audit-automation-gaps`, and
  `audit-permission-grants` route-out notes and the README's instruction-layer and migration
  sections. The `claude-memory` memory-layer skill was renamed `health` → `audit`; the old
  `/claude-memory:health` invocation no longer resolves.

### Removed

- **`audit-model-fit` skill superseded by `audit-instructions`.** Both audits answer the same
  question — locally-owned instruction surfaces vs current model capability — and repo doctrine
  admits only one skill per question. `audit-instructions` carries the fuller catalog (eleven checks
  I1–I11 with authority tags and evidence tiers), the `claude-memory` hygiene partition, and the
  adversarial fresh-context verify pass, so it strictly covers `audit-model-fit`'s four checks and
  supersedes it. Both were built concurrently from the same underlying issue (#800); `audit-model-fit`
  (added in 0.8.0 below) is removed here.

## [0.8.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.8.0]

### Added

- **`audit-model-fit` skill** (`/claude-config:audit-model-fit`). A fourth audit that sweeps the local
  Claude Code instruction surfaces — user + project `CLAUDE.md`, skill `SKILL.md` bodies + context
  files, agent definitions, `.claude/rules/**`, prompt-type hooks and output styles — for deterministic
  constraints that hobble newer, more capable models, and proposes removals/rewrites. Check catalog:
  bare prohibitions with no rationale (rewrite to add the *why*, never blanket-delete), over-prescriptive
  step lists (cull to intent + hard constraints), over-constraining example blocks (trim toward the
  recommended 3–5, not a blanket ban), and stale model-era workarounds — each measured against "would
  removing this cause Claude to make mistakes?". A bundled `instruction-surface-scan.sh` enumerates the
  surfaces and flags the two grep-able smells as candidates; the judgment stays in the skill body.
  **Report-only and human-gated**: it presents findings plus proposed diffs and never edits any
  instruction file itself (no `--fix`). Findings inside `melodic-software/standards`-managed
  materializations route upstream per the sync-manifest rather than being edited in place. Composes with
  (distinct intents, pointers only) `claude-memory:audit` (instruction-layer *health*, same surfaces),
  `skill-quality:check` (structure), `docs-hygiene:compress` (token brevity), and the sibling `audit`
  (config-file correctness). The plugin `description` now reads "Four audit skills".

## [0.7.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.7.0]

### Changed

- **BREAKING — two skills renamed to the `audit-*` naming grammar** (fleet conformance wave, naming
  grammar): `automation-gaps` → `audit-automation-gaps` (`/claude-config:automation-gaps` →
  `/claude-config:audit-automation-gaps`) and `permission-hygiene` → `audit-permission-grants`
  (`/claude-config:permission-hygiene` → `/claude-config:audit-permission-grants`). The old
  invocations stop resolving; update any saved references. The `audit` skill is unchanged.

## [0.6.0]

### Added

- **`setup` skill on the uniform contract** (`/claude-config:setup`). Closes the doctrine-tracked
  setup gap: the plugin's audit scripts require external CLIs (`jq` for all three skills, `curl` for
  the plugin-drift check) but no setup shipped. `check` (default, read-only) probes `jq`/`curl`/the
  bash shell against the bundled scripts as source of truth and reports PASS/FAIL/INFO — `jq` missing
  is a plugin-wide FAIL, `curl` missing a scoped FAIL for the drift check only. `apply` gives platform
  install guidance and re-verifies; it installs no system package and writes nothing. README
  Requirements now names the bash/Git-Bash shell prerequisite alongside `jq`/`curl`.

## [0.5.0]

### Changed

- Renamed the plugin `claude-config-audit` → `claude-config`. Reinstall as
  `claude-config@melodic-software` and update any `/claude-config-audit:*` invocations to the
  `/claude-config:*` namespace.
- Renamed the `settings-audit` skill → `audit` (`/claude-config:audit`) and the
  `automation-deep-dive` skill → `automation-gaps` (`/claude-config:automation-gaps`).
  `permission-hygiene` keeps its name (now `/claude-config:permission-hygiene`).

### Removed

- Extracted the `memory-health` skill into the new standalone `claude-memory` plugin, where it ships as
  the `health` skill (`/claude-memory:health`). Install `claude-memory@melodic-software` for the
  instruction/memory-layer audit.

## [0.4.0]

### Added

- "Pre-computed context" blocks in the `automation-deep-dive`, `memory-health`, and `settings-audit`
  skills: `!`-executed commands inject live repo facts (automation inventory; memory/rules/CLAUDE.md
  counts and the RD1/M2 script-backed check counts; installed Claude Code version) at skill load, so
  each audit starts from guaranteed-fresh evidence instead of relying on the model to remember to run
  the bundled scripts. Every command carries an `|| echo` fallback so skill load never hard-fails.
  No `allowed-tools` self-grant ships with the blocks: a `Bash(bash <path>*)` grant is the
  interpreter-led P1 shape this plugin's own `permission-hygiene` criteria flag (auto mode drops it),
  and `!`-execution does not route through `allowed-tools`.
