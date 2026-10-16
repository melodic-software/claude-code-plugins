---
bump: minor
---

### Added

- `/guardrails:setup apply install-read-deny [local|shared] [user] [remove]` prints the
  `Read()` deny rules for `.env` files (and, with `user` and your yes, `~/.ssh/**` and
  `~/.aws/**`) and adds or removes them in the settings file you choose.
- `block-dangerous-git` and `block-root-delete-target` ask instead of deny when a person is
  at the session (`CLAUDE_CODE_SESSION_ATTENDED` exactly `1`) and the guard read what would
  run, through the new `hooks/refuse.sh`. A command a guard cannot read is still denied.
- `run-guards.sh` keeps a permission decision when it merges several guards' output: deny
  over ask, the asking guards' reasons joined, and any guard's exit 2 still denies the call.

### Changed

- `block-credential-read` is now off by default: measured on local session logs, 6% of its
  refusals were right, below the ADR 0003 bar. Turn it back on with its
  `block_credential_read_enabled` option. The per-guard figures are in
  `docs/conventions/hook-precision/guard-precision.md`; `block-hook-bypass` is removed (see
  Removed).
- `block-noncanonical-commit` now blocks a `git commit -m` message holding a `$` or a backtick
  the shell expands (double quotes or none in Bash, double quotes or `@"` in PowerShell), and no
  longer blocks a message only because it spans several lines.
- `block-credential-read` covers interpreter reads (`python3 -c`, `node -e`, `ruby -e`,
  `perl -e`, `php -r`, and a heredoc fed to one) of credential files, now including
  `~/.ssh/id_*` and `~/.aws/credentials`. `cat` of those files is left to native `Read()` deny
  rules.

### Fixed

- `block-root-delete-target` no longer blocks `X=build && rm -rf "$X"`: when the whole
  command is exactly `NAME=LITERAL`, one `&&`, `;` or newline, then an `rm` whose only
  expansions are `"$NAME"` or `"$NAME/..."` (a plain suffix inside the double quotes), the
  variable is judged as that literal. An unquoted `$NAME` binds nothing, since an inherited
  IFS can split it. Any other command, including a comment, a second statement, a
  braced `${NAME}` or a name the shell sets itself, still blocks the variable.
- An attended ask is the verdict on the whole command: any denying segment, budget or parse
  cap anywhere in it denies, and one ask names every asking segment.
- `block-noncanonical-commit` reads the literal spelling of the `-m` argument itself, not a
  matching spelling elsewhere in the command.
- `block-noncanonical-commit` leaves `-m "$msg"` and `-m "$(...)"` alone: a value that is one
  variable or one command substitution is meant to expand. Text after the substitution inside
  the quotes (`-m "$(true) $HOME"`, or after a quoted heredoc's `)`) still blocks, as does a
  PowerShell `$` after an escaped `""`.
- `block-credential-read` no longer treats a shell name inside an argument, such as a grep
  pattern, as a shell that runs the rest of the command.
