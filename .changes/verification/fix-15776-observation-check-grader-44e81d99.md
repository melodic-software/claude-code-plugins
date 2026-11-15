---
bump: none
---

Changes an eval grader only: the `names-observation-check` regex in `confirm-failed-check-observation-first` now reads the stale-capture reason from the bullet lines under the `Observation check` label and accepts "older", "before the build" and "before the diff", so correct answers no longer fail it.
