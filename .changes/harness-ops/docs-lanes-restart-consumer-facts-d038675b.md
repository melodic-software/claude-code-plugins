---
bump: patch
---

### Changed

- `/harness-ops:lanes` states that `consume-restarts run` relaunches a stopped lane whose telemetry
  carries a `restart_request` once the operator registers its OS schedule, and that a crashed lane
  writes none, so it stays down until the operator restarts it.
- `/harness-ops:lanes` states that a lane can read its own context zone from the context-guard
  snapshot in `-p` and `--bg` sessions, but still cannot reset its own context from inside the loop.
