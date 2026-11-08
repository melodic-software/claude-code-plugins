---
bump: patch
---

### Fixed

- `inventory` finds the Claude Code binary of the session it runs in, through `CLAUDE_PID`, before searching `PATH` and the usual install roots. A CI lane that installs the CLI outside both (the release lane's native-drift pass) no longer reads no binary, reports version `unknown`, and files an `inventory-broken` item.
