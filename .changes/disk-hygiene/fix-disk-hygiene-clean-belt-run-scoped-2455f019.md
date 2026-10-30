---
bump: patch
---

### Fixed

- An audit-only `/disk-hygiene:clean` no longer locks the rest of the session out of `gh`, `git` and test commands. The skill's belt now denies only while a clean run is open, tracked by a per-session marker in a new engine-owned `clean-runs/` directory under the plugin data directory. A `preview` opens the run, which stays open until the run's `apply` or `handoff-apply` writes its report, or the preview ends in `manual-handoff-lane` or `blocked` (the engine now writes `<plan>.run-end.json` for those outcomes). A `handoff-apply` with no preview holds the belt until its report lands, and each manual-lane `handoff-verify` holds it until an hour passes with no engine call. A `scan` alone opens no run. The marker fails closed: one the guard cannot parse holds the belt until the hour passes, and a payload with no session id keeps it on. The guard never deletes the marker, and a later engine call cannot revive an ended or timed-out run. The engine gate, the approval token and the belt's verdicts during a run are unchanged; the residual that a session can write the end file itself is recorded in the safety model.
