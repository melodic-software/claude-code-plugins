---
bump: patch
---

### Fixed

- A pr-unblock run whose credential was refused (`class=auth`, a 401) now counts as a limit stop: its head waits `limits.fallback-reset` hours before the next dispatch instead of spending all `limits.limit-stops-per-head` runs at once, and the dispatcher logs a notice naming the class and the reset time (`.github/scripts/pr-unblock/limit-stop.mjs`, `dispatch.mjs`).
- `pr-run-activity-read.yml` now puts the lane record's class and reset on the check run it posts, so `limit-stop.mjs` can tell a usage limit or a refused credential from any other failure on resolve-conflicts, address-feedback and review-dependency checks; before, every such check read as a plain failure.
