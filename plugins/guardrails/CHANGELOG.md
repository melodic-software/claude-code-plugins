# Changelog

All notable changes to the `guardrails` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.9.0]

### Added

- **`block-noncanonical-commit` — `git commit` must pipe its message via `-F -`.** The advisory that
  previously covered this was overridden 11 times in a single session; an advisory that is always
  overridden trains the reader to filter it out. The guard enforces the *mechanic*, not the ritual:
  `git commit -m "<multi-line>"` flattens newlines unpredictably across shells, and the stdin form is
  what prevents it. Exempt, because no message-on-stdin form exists for them and gating them would
  strand real work: `--amend`/`--no-edit`, `-C`/`-c`/`--reuse-message`/`--reedit-message`,
  `--fixup`/`--squash`, `-F <path>`, and any commit taken while a merge, rebase, cherry-pick, or
  revert is in progress. Kill switch `block_noncanonical_commit_enabled`; allow-list
  `block_noncanonical_commit_allow` (`message-flag` permits a bare `-m`). Detection reuses the
  argv-grammar-faithful parser, so `bash -lc` wrappers resolve and a commit body merely *mentioning*
  `git commit -m` never fires. Inline aliases are expanded before the subcommand verdict, closing the
  hole where `git -c alias.c=commit c -m x` reads as subcommand `c` and walks straight through.

### Fixed

- **`flag-commit-pr-skill-bypass` no longer demands `--trailer`.** The old condition required both
  `-F -` **and** `--trailer`, but `/commit` omits the trailer when the resolved `trailer_policy` is
  `none` — so in a repo whose convention forbids a co-author trailer, the skill's own conformant
  output was flagged on every commit. The trailer is policy; only the stdin form is mechanic. This
  also had to be settled before the new guard could block on the same condition: requiring
  `--trailer` to pass would have permanently blocked `/commit` in that configuration.

### Changed

- **`flag-commit-pr-skill-bypass` is now `gh pr create`-only.** The `git commit` branch moved to
  `block-noncanonical-commit`, so the two never double-fire on one command. `gh pr create` stays
  advisory and cannot become otherwise: `/pull-request create` issues that exact command itself, and
  [anthropics/claude-code#22655](https://github.com/anthropics/claude-code/issues/22655) (expose
  `skill_name` to hooks) is closed as not planned — a hook cannot tell a skill-driven call from an
  ad hoc one, so blocking it would deadlock the skill.

## [0.8.0]

### Changed

- All seven hook entry scripts read stdin via the shared `hook::buffer_stdin` helper
  (bounded `read -t`, default 2s) instead of a bare `cat`, so a Windows Win32-pipe
  late-EOF stall can no longer hang a hook — and with it every tool call — indefinitely.
- **Blocking guards now fail closed on a stdin read timeout.** When `hook::buffer_stdin`
  returns 2 (the read timed out before a complete JSON payload arrived), the five
  blocking guards (`block-dangerous-git`, `block-hook-bypass`, `block-no-verify`,
  `secret-pattern-detection`, `hardcoded-path-check`) exit 2 with the BLOCKED reason on
  stderr instead of skipping: a guard that could not evaluate the tool call must not
  wave it through. Empty stdin still skips, matching the previous empty-payload
  behavior. The two advisory hooks (`flag-commit-pr-skill-bypass`,
  `workflow-resilience-check`) skip on any read failure, as before.

## [0.7.1]

### Fixed

- **`flag-commit-pr-skill-bypass` jq-absent skip is now visible** (prerequisite-visibility
  doctrine). The hook previously no-op'd silently when `jq` was missing; it now writes the
  same one-line stderr notice its sibling guardrails hooks emit ("advisory disabled —
  install jq to enable") before exiting 0.

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
