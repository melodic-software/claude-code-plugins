---
bump: patch
---

### Fixed

- **`block-unresolved-pr-merge` no longer counts a check run that a newer run of the same check superseded (#7473).** The head commit's check-runs endpoint can list two runs of one check, such as a draft run that failed and the run after the ready flip that passed, and the guard blocked on the older failure while GitHub reported the PR clean. It now judges only the newest run per check name and app, by completion time, else start time. A newest run that failed still blocks, and a newest run still pending still blocks an immediate merge.
