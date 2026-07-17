# Changelog

All notable changes to the `guardrails` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.0]

### Added

- **`block-dangerous-git` guard** (PreToolUse on Bash, blocking): stops irreversible git operations
  before they run — `push --force`/`-f` (never `--force-with-lease`), `reset --hard`, `clean` with a
  force flag, and worktree-wide `checkout .` / `restore .` (path-scoped forms and index-only
  `restore --staged .` pass). `branch -D` is deliberately not blocked: deleted refs are
  reflog-recoverable and sanctioned skill flows issue it inline. Per-repo/per-user allow-list via
  `HOOK_BLOCK_DANGEROUS_GIT_ALLOW` (comma list of `push-force`, `reset-hard`, `clean-force`,
  `checkout-dot`, `restore-dot`) in a settings `env` block; kill switch
  `HOOK_BLOCK_DANGEROUS_GIT_ENABLED=false`. Capability adapted from mattpocock/skills
  `git-guardrails-claude-code`; the implementation is the house argv-grammar parser, whose word-exact
  matching avoids upstream's substring false-blocks (all `git push` blocked; `checkout .github/…`
  matching `checkout .`).

### Changed

- The argv-grammar tokenizer, git-executable resolver, and subcommand walk that `block-no-verify`
  carried privately moved into the shared hook-utils library (`hook::bash_parse_segments`,
  `hook::git_resolve_index`, `hook::git_resolve_subcommand`) so both git guards share one parser.
  `block-no-verify` behavior is unchanged with one alignment: the `core.hooksPath` block now applies
  exactly to `git commit` / `git push` (its documented scope) instead of firing on any git
  subcommand mid-walk.
