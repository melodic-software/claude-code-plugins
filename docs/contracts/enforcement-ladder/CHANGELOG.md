# Changelog for the enforcement-ladder convention

Notable changes to the enforcement ladder (SemVer). Renaming, removing or moving a rung is a major
bump. Adding a rung, a reader's selection rule or a boundary-rule location is a minor bump.
Wording-only clarification is a patch.

## [2.0.0] - 2026-10-21

The ladder becomes four tiers (codebase, static analysis, guidance, human only), strongest first,
with a "runs at" column on the static-analysis rungs and one "Guardrail criterion" section.

- Renamed: `canonical-helper` to `shared-helper`; `hook` to `action-guard`; `llm-only` to
  `automated-review`.
- Added: `harness-setting`, `scaffold`, `instruction`, `skill`, `human-review`.
- Moved: `shared-helper` from below the linters to tier 1, after `make-impossible`, and it counts
  there only when a lint or check names the helper; `action-guard` now follows `harness-setting`
  and precedes `scaffold` in tier 2; the `CLAUDE.md`, `AGENTS.md` and rules-file routing of the old
  `llm-only` rung is now `instruction`, and project docs are `human-review`.
- Removed as rungs: "Git hook or CI" (a place a check runs, now the "runs at" column) and the
  code-content hook (the same check as a linter rule or a test).
- Unchanged ids: `make-impossible`, `editorconfig-severity`, `analyzer-pack-rule`,
  `custom-analyzer`, `semgrep-rule`, `architecture-test`.
- Added the Guardrail criterion (eight conditions), the forgotten-versus-ignored rule for a
  recurring correction, and the selection rows updated to the new ids.

## [1.0.0] - 2026-10-04

Initial ladder: one strongest-first rung list, from `make-impossible` through compiler settings,
the four analyzer and linter rungs, `canonical-helper`, `architecture-test`, tests, git hook or CI,
`hook` and `llm-only`; the list of places boundary rules live; the selection rules of
`/harness-config:audit-automation-gaps`, `/review:audit-enforceability` and `/session-flow:retro`
codify; reordering through project instructions; and the codebase and its history as the memory.
