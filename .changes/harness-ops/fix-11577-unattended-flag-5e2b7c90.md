---
bump: minor
---

### Changed

- `/harness-ops:audit-install-state`, `/harness-ops:audit-performance` and `/harness-ops:audit-skill-visibility` take `--unattended` in place of the bare word `unattended`, accepted anywhere in their arguments. Each skill still takes the flag out before running its engine script, whose parser does not accept it. The bare word stops the run and names `--unattended`, so it never reaches `audit-install-state`'s root slot. The argument hints list `--unattended`, and the `audit-install-state` eval passes the flag.
