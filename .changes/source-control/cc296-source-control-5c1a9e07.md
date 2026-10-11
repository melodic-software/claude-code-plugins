---
bump: patch
---

### Fixed

- **The PR monitor's Monitor watch arms again on current Claude Code.** `/source-control:pull-request monitor` armed its watch with a `persistent` option that Claude Code no longer accepts, so the call failed and the PR went unwatched. The watch now passes an explicit `timeout_ms`, re-arms on the deadline notice while the PR still needs watching, and runs one full iteration after each re-arm so nothing that landed in the gap is missed. The poll's first pass records the current checks without emitting them, so a re-arm no longer replays every finished check. The pull-request skill, the babysit loop, and the plugin README now describe a watch that is re-armed at each deadline rather than a session-long one.
- **The monitor no longer depends on `TaskList`.** Finding and stopping an existing watch now uses the task id the session got back when it armed the watch, because current models do not get the task-tracking tools by default.
- **The cloud fallback poll survives the background time limit.** Where the Monitor tool is unavailable, the `run_in_background` poll now passes an explicit `timeout` and starts again when the stop notice arrives, so a long CI run in an unattended session is no longer cut off.
