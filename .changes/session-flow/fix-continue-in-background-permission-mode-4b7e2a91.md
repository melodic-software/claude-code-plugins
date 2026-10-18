---
bump: patch
---

### Fixed

- `continue-in-background` launches the `claude --bg` session with `--permission-mode auto`, so a permission ask no longer waits for an attach while the user is away; an action auto mode denies is reported in the launched session's final hand-off.
