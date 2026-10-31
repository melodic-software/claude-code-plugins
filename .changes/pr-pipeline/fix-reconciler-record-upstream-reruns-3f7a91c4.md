---
bump: patch
---

### Fixed

- The lost-run reconciler now records each hosted review run it re-runs after an upstream stop, as
  `reconcile-rerun-<run id>-2-<head>`, before it re-runs it. A pass uploads at most three records,
  so a PR or lane run whose records would pass that waits for a later pass.
- ci-status's upstream-stop message now says the review's dispatch re-runs ci-status under that
  record, and a person re-runs it only if that re-run does not come.
