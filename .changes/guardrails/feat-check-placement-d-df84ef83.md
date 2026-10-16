---
bump: minor
---

### Added

- `/guardrails:setup apply install-read-deny [local|shared] [user] [remove]` prints the
  `Read()` deny rules for `.env` files (and, with `user` and your yes, `~/.ssh/**` and
  `~/.aws/**`) and adds or removes them in the settings file you choose.
- `block-dangerous-git` and `block-root-delete-target` can ask instead of deny when a person
  is at the session (`CLAUDE_CODE_SESSION_ATTENDED` exactly `1`), through the new
  `hooks/refuse.sh`. Under the shipped dispatcher they still deny, because its merge of
  several guards' output keeps no permission decision.

### Changed

- `block-credential-read` and `block-hook-bypass` are now off by default: measured on local
  session logs, 6% and 35% of their refusals were right, below the ADR 0003 bar. Turn either
  back on with its `_enabled` option. The per-guard figures are in
  `docs/conventions/hook-precision/guard-precision.md`.
- `block-noncanonical-commit` now blocks a `git commit -m` message holding a `$` or a backtick
  the shell expands (double quotes or none in Bash, double quotes or `@"` in PowerShell), and no
  longer blocks a message only because it spans several lines.
- `block-credential-read` covers interpreter reads (`python3 -c`, `node -e`, `ruby -e`,
  `perl -e`, `php -r`, and a heredoc fed to one) of credential files, now including
  `~/.ssh/id_*` and `~/.aws/credentials`. `cat` of those files is left to native `Read()` deny
  rules.

### Fixed

- `block-root-delete-target` no longer blocks `S=build; ...; rm -rf "$S"`: a variable an
  earlier statement of the same command sets to a plain literal is judged as that literal,
  unless a later statement may change it.
- `block-noncanonical-commit` leaves `-m "$msg"` and `-m "$(...)"` alone: a value that is one
  variable or one command substitution is meant to expand.
- `block-credential-read` no longer treats a shell name inside an argument, such as a grep
  pattern, as a shell that runs the rest of the command.
