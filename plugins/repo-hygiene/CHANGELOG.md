# Changelog

All notable changes to the `repo-hygiene` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0]

### Added

- **`remove-path.sh` — guarded orphaned-path removal.** A new `clean` skill action that
  removes a whole orphaned clone or leftover directory under the ghq root (`--root`
  overrides) — the whole-directory deletion the selective tiers never perform (e.g. a local
  clone whose upstream repository was deleted). Defaults to `--dry-run`; it is not composed
  into any tier and runs only on explicit request. Guards refuse the containment root,
  symlink/reparse-point targets, and linked worktrees, and block any repo with uncommitted
  changes, stash entries, registered worktrees, ignored secret-class files
  (`--include-secrets` to override), or unpushed work (`--allow-unpushed` to override).

## [0.2.1]

### Fixed

- The `clean` skill's PreToolUse destructive-guard hook now uses the
  interpreter-named exec form (`command: "bash"`,
  `args: [".../destructive-guard.sh"]`) instead of naming the bare `.sh` as
  the command — the doctrine-prescribed Windows-safe spawn shape
  (cross-platform declaration wave).

## [0.2.0]

### Changed

- **Destructive-guard kill switch migrated to native `userConfig`** (the fleet-wide
  kill-switch doctrine ruling): the `clean_destructive_guard_enabled` boolean (default
  `true`) now gates the session-scoped destructive guard, read through the native
  `CLAUDE_PLUGIN_OPTION_CLEAN_DESTRUCTIVE_GUARD_ENABLED` hook-process mirror. Configure
  with `/plugin configure repo-hygiene` or `claude plugin install --config`.
- **BREAKING:** the `HOOK_CLEAN_DESTRUCTIVE_GUARD_ENABLED` environment variable is retired
  and no longer read. Zero-config behavior is unchanged (guard active while the clean skill
  is active).
