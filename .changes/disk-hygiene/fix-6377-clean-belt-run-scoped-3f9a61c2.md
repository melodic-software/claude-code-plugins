---
bump: patch
---

### Fixed

- The `/disk-hygiene:clean` session belt now holds only while a clean run is open, not until the session ends. A run opens when the guard admits a `preview`, `apply`, `handoff-apply` or manual-lane `handoff-verify`. It ends when the step's end file appears: the report an `apply` or `handoff-apply` writes, or the file the engine now writes when a preview's outcome is `manual-handoff-lane` or `blocked`. It also ends after an hour with no engine call. A completed or refused `scan` with no preview after it is an audit-only outcome and leaves the belt off, so later `gh`, `git` and test commands run in the same session. Outside a run, Bash and PowerShell commands that do not name the engine answer to the session's own permission rules. The guard keeps one marker per session under the plugin data directory and fails closed: a marker it cannot parse holds the belt until the hour passes, and a payload with no session id keeps the belt on. The engine gate, the approval token and the belt's verdicts while a run is open are unchanged.
