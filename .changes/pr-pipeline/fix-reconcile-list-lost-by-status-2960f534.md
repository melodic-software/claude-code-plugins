---
bump: patch
---

### Fixed

- The lost-run reconciler lists pr-verify runs once per lost conclusion and per not-yet-completed status instead of all runs of the day, so a day with more than 500 runs no longer fails the page cap.
