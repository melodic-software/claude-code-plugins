# Changelog

All notable changes to the `guardrails` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.7.0]

### Added

- **`/guardrails:setup` skill on the uniform contract** (fleet conformance
  wave, dim 8). `check` reads the guard scripts and `hooks.json` as the
  source of truth and probes Bash 5.0+, `jq` (absence = every guard fails
  open — surfaced as the FAIL it is), each guard's effective toggle, the
  `cli-flag-verify` scan surface, and the `block-dangerous-git` allowlist.
  `apply` is guidance-only with no write path; reconfiguration guidance
  states `--config`'s fresh-install-only semantics. All-toggles-disabled
  downgrades prerequisite FAILs to INFO.

## [0.6.2]

### Changed

- Header comment ordering in `machine-path-patterns.sh` corrected to the `shell=bash` →
  description → pragma → code convention: the `SC2034` disable and its rationale comment now
  sit immediately before the pattern definitions they guard, instead of ahead of the module
  description. Comment-only change; pattern bodies are unchanged.

## [0.6.1]

### Changed

- **Per-OS machine-path regex bodies sourced from a shared, standards-managed file.** The five
  `HPP_*` pattern bodies (`HPP_WIN_USER_BODY`, `HPP_MACOS_USER_BODY`, `HPP_LINUX_USER_BODY`,
  `HPP_WIN_REPO_BODY`, `HPP_ESCAPED_WIN_REPO_BODY`) — previously a hand-synced copy of the same
  bodies carried by `ci-workflows`' `machine-specific-paths` action and `medley`'s
  `tools/shared/path-detection` — now live in `machine-path-patterns.sh`, the org's
  standards-managed materialization (`melodic-software/standards#172`). `hardcoded-path-patterns.sh`
  sources it and keeps only its own scan wrapping (OS-context suppression, exclusion pipes).
  Patterns are byte-identical to the prior inline copy; no behavior change.

## [0.6.0]

### Added

- **`block-dangerous-git` guard** (PreToolUse on Bash, blocking): stops irreversible git operations
  before they run — `push --force`/`-f` (never `--force-with-lease`), the equivalent
  leading-`+` refspec and `--mirror` force-push forms (a push dry-run disarms), `reset --hard`,
  `clean` with a force flag (a dry-run flag anywhere disarms the check — git honors it regardless
  of order), worktree-wide `checkout`/`restore` pathspecs (`.`, `:/`, exclude-only sets, and
  long-form magic carrying `top`; path-scoped forms and index-only `restore --staged .` pass), and
  forced `checkout -f`/`--force` and `switch -f`/`--discard-changes` (both throw away local
  modifications). Accepted unique-prefix abbreviations of the blocked long options match too
  (git parse-options accepts them: `reset --h` runs `--hard`). The parse-cap fail-closed path
  never consults the allow-list. `branch -D` is deliberately not blocked: deleted refs are
  reflog-recoverable and sanctioned skill flows issue it inline. Per-repo/per-user allow-list via
  the `block_dangerous_git_allow` userConfig option (comma list of `push-force`, `reset-hard`,
  `clean-force`, `checkout-dot`, `restore-dot`, `checkout-force`); kill switch the
  `block_dangerous_git_enabled` userConfig option set to false. Capability adapted from
  mattpocock/skills `git-guardrails-claude-code`; the implementation is the house argv-grammar
  parser, whose word-exact matching avoids upstream's substring false-blocks (all `git push`
  blocked; `checkout .github/…` matching `checkout .`).

### Changed

- The argv-grammar tokenizer, git-executable resolver, and subcommand walk that `block-no-verify`
  carried privately moved into the shared hook-utils library (`hook::bash_parse_segments`,
  `hook::git_resolve_index`, `hook::git_resolve_subcommand`) so both git guards share one parser.
  `block-no-verify` behavior is unchanged with one alignment: the `core.hooksPath` block now applies
  exactly to `git commit` / `git push` (its documented scope) instead of firing on any git
  subcommand mid-walk.

## [0.5.1]

### Changed

- Shared `hook-utils.sh` resynced with the fleet's new prerequisite-visibility
  helpers (jq-free notice emitters, once-per-session gate, jq gate). No
  behavior change for this plugin's guards: their documented jq fail-open with
  a stderr notice is unchanged.

## [0.5.0]

### Changed

- **Per-hook kill switches and tuning scalars migrated to native `userConfig`** (the
  fleet-wide kill-switch doctrine ruling). Each guard's toggle is now a `userConfig`
  boolean named `<guard>_enabled` (default `true`), read by the hooks through the
  native `CLAUDE_PLUGIN_OPTION_<KEY>` hook-process mirror; `cli-flag-verify`'s binary
  set and skip list are now the `cli_flag_verify_bins` / `cli_flag_verify_skip_bins`
  options. Configure interactively with `/plugin configure guardrails` or headless via
  `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_<NAME>_ENABLED`, `HOOK_CLI_FLAG_VERIFY_BINS`, and
  `HOOK_CLI_FLAG_VERIFY_SKIP_BINS` environment variables are retired and no
  longer read. A consumer that set any of these in a
  settings `env` block must re-express the value as the matching `userConfig` option.
  Zero-config behavior is unchanged (all guards on, same defaults). The
  `HOOK_TELEMETRY_SINK` consumer-side telemetry seam is unaffected.
