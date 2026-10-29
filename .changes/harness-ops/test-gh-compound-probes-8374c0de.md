---
bump: minor
---

### Added

- `/harness-ops:behavior-probes`: an `intake-permissions` area that checks, under `dontAsk` with only `Bash(gh issue view *)` allowed, that a plain `gh issue view` runs and that the `;`, `&&`, `|` and `$()` forms adding a second command are denied. A stub `gh` logs the calls, so a failed deny touches no real issue.
