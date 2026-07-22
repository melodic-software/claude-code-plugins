# Changelog

All notable changes to the `claude-memory` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.3]

### Fixed

- **Non-repo memory-dir resolution implemented (the documented fallback).** The shared
  `resolve-memory-dir.sh` hard-required a git repo (`exit 1` when `git rev-parse --show-toplevel`
  was empty) and the `stateless` skill's `scope-report.sh` pre-emptied it with a bail-out telling
  the user to run from within a repo — but the official memory doc (re-verified 2026-07-22)
  says "Outside a git repo, the project root is used instead", so a non-repo directory is a
  fully valid case with a real memory store the skill could neither find nor report. The
  resolver now derives the project slug from the current directory (same Windows-form
  normalization as the repo-root path) when no repo is found, `scope-report.sh` calls it
  unconditionally (with an informational note that the cwd is the project key), and the
  regression test that had locked the bail-out in as a spec now asserts the resolved
  cwd-derived path. The `audit` skill's deterministic M2 checker
  (`memory-index-refs-check.sh`) carried its own now-redundant git-repo guard that would have
  kept the audit from checking a non-repo store's index integrity — the guard is removed
  (the shared resolver owns the non-repo case) with a non-repo regression test added. (#978)

## [0.3.2]

### Added

- **`audit` skill: reciprocal scope-boundary note.** Model-era instruction-content findings
  (prior-model workarounds, over-prescriptive scaffolding, bare prohibitions, reasoning-echo
  directives, stale example scaffolding) now route to the `claude-config` plugin's
  `audit-instructions` skill when that plugin is installed; absent it, such observations stay
  in the audit report criteria-free rather than being judged against this checklist or
  silently dropped. Completes the partition that skill declared toward this one.

## [0.3.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.3.0]

### Added

- **New `stateless` skill (`/claude-memory:stateless`)** for inspecting and disabling Claude
  Code auto memory — the notes Claude writes for itself per repo under
  `~/.claude/projects/<project>/memory/` (relocatable via `autoMemoryDirectory`). Actions:
  `status` (default, read-only — effective on/off state and store contents across all settings
  scopes), `disable` (sets `autoMemoryEnabled: false` and `CLAUDE_CODE_DISABLE_AUTO_MEMORY` in a
  confirmed scope, and flags a dotfile-manager backfill for a tracked `settings.json`), and
  `purge` (destructive — reads `autoMemoryDirectory` at every scope, shows a deletion manifest,
  and deletes auto-memory `*.md` files only after explicit confirmation). Scope is auto-memory
  only; the instruction layer stays with `audit`, and transcripts/history are out of scope
  (auto-cleaned by `cleanupPeriodDays`). Claude Desktop / claude.ai account memory is a
  server-side store the skill gives direction for rather than deleting locally. Per the
  env-vars doc, `CLAUDE_CODE_DISABLE_AUTO_MEMORY` overrides `autoMemoryEnabled` (the env var is
  authoritative when set); `disable` writes the env var (`1`) plus `autoMemoryEnabled: false`,
  and `status` treats a set env var as authoritative. The bundled `scope-report.sh` reuses the
  plugin's single-source memory-dir resolver rather than re-deriving the path.

### Fixed

- **`resolve-memory-dir.sh` now honors `CLAUDE_CONFIG_DIR`.** The shared resolver (used by both
  the `audit` and `stateless` skills) resolved the config root as `$HOME/.claude`, so a machine
  that relocates its Claude Code config via `CLAUDE_CONFIG_DIR` had its memory directory resolved
  to the wrong path. It now uses `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, per the official
  `.claude-directory` doc, so the relocated `projects/<project>/memory/` tree resolves correctly.

## [0.2.3]

### Fixed

- **`orphan-rule-check` no longer truncates a quoted `memory_dir` at an interior `#`.**
  Seam resolution now routes through the shared `parse-concern-value.sh` helper
  (materialized from `lib/parse-concern-value.sh`), which resolves surrounding quotes
  *before* stripping comments: `memory_dir: ".scratch#dir"` keeps its `#` and the correct
  tier is excluded from the reference search, rather than collapsing to `.scratch` and
  masking an orphan rule. The naive `${seam%%#*}`-first strip is gone; an unquoted
  whitespace-preceded trailing `# comment`, surrounding whitespace, and trailing-slash
  handling are unchanged. As a
  non-interactive detector it still degrades to the documented `.work` default when the
  seam is unset — the contract's inferred/interactive rungs stay the calling skill's job.
- **A comment-only `memory_dir` now resolves to the fallback, not a literal directory.**
  `memory_dir: # use default` is YAML-null; the parser previously kept `# use default`
  as the value (its comment strip only fired on a whitespace-*preceded* `#`), so the
  detector searched `# use default/` and stopped excluding the default `.work/` tier —
  letting a `.work` reference mask an orphan. A `#` that starts the unquoted value is now
  treated as a comment, so resolution falls through to the caller's fallback / documented
  default.

## [0.2.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.2.1]

### Fixed

- **`orphan-rule-check` now resolves the excluded memory tier from the topic-docs seam**
  instead of hardcoding `.work/`. The reference search reads `memory_dir` from
  `.claude/topic-docs.yaml` (falling back to `.work/` when unset) and excludes that path,
  so a consumer that overrides `memory_dir` no longer has its real memory tier scanned —
  ephemeral files there can no longer register false references that mask an orphan rule.

## [0.2.0]

### Changed

- **BREAKING — the `health` skill renamed to `audit`** (fleet conformance wave, naming grammar):
  `/claude-memory:health` → `/claude-memory:audit`. The old invocation stops resolving; update any
  saved references. Actions (`audit` / `fix` / `update` / `report`) are unchanged.

## [0.1.0]

### Added

- Initial release. The `health` skill was extracted from the `claude-config-audit` plugin — where it
  shipped as the `memory-health` skill — into this standalone plugin, invoked as `/claude-memory:health`.
  It audits the Claude Code instruction/memory layer (`CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/`,
  and auto-memory) against a checklist derived from official Claude Code documentation, with a
  deterministic script-backed spine (MEMORY.md index integrity, orphan always-loaded rules) and
  `audit` / `fix` / `update` / `report` actions. Audit reports stay contributor-local in the plugin's
  data directory.
