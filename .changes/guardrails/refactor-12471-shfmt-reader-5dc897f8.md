---
bump: patch
---

### Added

- The shared `hook-utils.sh` gains `hook::bash_parse_segments_shfmt`, a Bash command reader on
  `shfmt --to-json` with the same callback and `HOOK_SEG_*` contract. `HOOK_BASH_READER=shfmt`
  selects it; the default reader is unchanged. It refuses the call when shfmt or jq is missing,
  fails or runs past 5 seconds, and the refusal names which of those happened, quoting shfmt's
  syntax error. It uses a shfmt in `~/.local/bin` when PATH has none.
- In a cloud session (`CLAUDE_CODE_REMOTE=true`), a SessionStart step installs the pinned,
  hash-checked shfmt v3.14.1 into `~/.local/bin` when none resolves. It never blocks the session;
  when the install fails, the reader's refusal message gives the reason.

### Fixed

- The PowerShell reduction the git guards parse as Bash no longer hands on a statement that opens
  with the `&` call operator or an empty `;` statement (one a blanked statement leaves), which
  bash's grammar has no reading for. The commands each guard sees are unchanged.
- `block-unresolved-pr-merge` parses a PowerShell command with its backtick escapes dropped, since
  PowerShell passes the escaped character on and Bash would read a backtick as a substitution.
