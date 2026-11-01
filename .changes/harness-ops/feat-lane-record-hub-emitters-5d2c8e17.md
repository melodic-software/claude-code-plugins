---
bump: patch
---

### Fixed

- `/harness-ops:morning-brief` drops a lane-outcome record marked `"handoff":true` before it classes a lane run, so a run whose first leg handed off is counted once, by the leg that carried it, in the failure-class, limit-stop, turn-headroom and model-usage lines.
