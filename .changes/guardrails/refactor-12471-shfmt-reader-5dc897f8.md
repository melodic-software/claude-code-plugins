---
bump: minor
---

### Changed

- The shared `hook-utils.sh` reads Bash commands from `shfmt --to-json` (`hook::bash_parse_segments`
  keeps its callback and `HOOK_SEG_*` contract), and the hand-written segmenter is removed. It
  refuses the call when shfmt or jq is missing, fails, runs past 5 seconds, or rejects the text
  (an unclosed here-doc, for one, which bash runs with a warning), and the refusal names which of
  those happened, quoting shfmt's syntax error. It uses a shfmt in `~/.local/bin` when PATH has
  none. The 5-second bound is the `read -t` builtin, so a parse forks the same processes on every
  run and needs no `sleep` or `timeout` command.
- A `git --config-env=<key>=$(…)` whose alias name comes from a substitution is denied: the
  substitution decides which variable's `!` alias git runs, and the guard cannot read it.

### Added

- In a cloud session (`CLAUDE_CODE_REMOTE=true`), a SessionStart step installs the pinned,
  hash-checked shfmt v3.14.1 into `~/.local/bin` when none resolves. It never blocks the session;
  when the install fails, the reader's refusal message gives the reason.

### Fixed

- The PowerShell reduction the git guards parse as Bash no longer hands on a statement that opens
  with the `&` call operator or an empty `;` statement (one a blanked statement leaves), which
  bash's grammar has no reading for. The commands each guard sees are unchanged.
- `block-unresolved-pr-merge` parses a PowerShell command with its backtick escapes dropped, since
  PowerShell passes the escaped character on and Bash would read a backtick as a substitution.
