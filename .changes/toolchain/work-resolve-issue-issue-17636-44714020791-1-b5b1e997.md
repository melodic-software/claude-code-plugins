---
bump: patch
---

### Fixed

- `/toolchain:check` and `/toolchain:lint` count a run as attended only when the session holds a
  message a person wrote other than the one that started the run, such as an earlier turn or a
  reply to an earlier question (#17636). A run with no such message counts as unattended, so it no
  longer falls back to a bundled default. This includes a session whose first message is
  `/toolchain:check` or `/toolchain:lint`: that run asks nothing, installs nothing, and
  `--code-fix` without `--yes` stops after the plan. For an attended run, send the command after
  any other message in the session.
