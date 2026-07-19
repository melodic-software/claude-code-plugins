# Changelog

All notable changes to the `codebase-health` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.0]

### Changed

- **`setup` split onto the uniform check/apply contract.** `check` inspects the effective merged
  `.claude/codebase-health.md` config read-only across its user-global → team → local overlay layers
  (presence — absent is INFO, since the audit re-infers targets each run — dimension source-list
  validity, tracked-not-ignored, and overlay divergence) and reports a PASS/FAIL/INFO table; `apply`
  runs the interview-infer-write flow, then re-runs `check` to verify the written file. The inference,
  example-claims, and layer-merge logic are unchanged; the read-only inspection path and the
  `check | apply` argument-hint are new.

## [0.4.0]

### Changed

- Renamed the plugin `codebase-audit` → `codebase-health` and its audit skill `codebase-audit` → `audit`.
  The audit invocation is now `/codebase-health:audit` (setup is `/codebase-health:setup`). Existing
  installs migrate automatically through the marketplace renames map.
- Renamed the consumer config-file convention `.claude/codebase-audit.md` → `.claude/codebase-health.md`
  (setup writes it, audit reads it). Re-run `/codebase-health:setup` to scaffold the new file; migrate
  any existing config manually.

## [0.3.0]

### Added

- Eval covering the scope-boundary decline: declining claim-extraction fan-out over
  `settings.json` / `.mcp.json` / hooks / permissions and routing to the adjacent
  `claude-config-audit` plugin's `/claude-config-audit:settings-audit` skill (or stating
  out-of-scope when that plugin is not installed) — behavior already documented in SKILL.md,
  now regression-tested.

## [0.2.0]

### Added

- Optional background/unattended execution variant for the Phase 1 per-file fan-out: the same
  discovery can run as a saved workflow (background execution, same-session resume, rerunnable
  script) when the environment provides such a surface; the in-session fan-out remains the default.
