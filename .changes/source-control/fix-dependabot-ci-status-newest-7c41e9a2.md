---
bump: patch
---

### Fixed

- pr-merge's Dependabot gate now decides `ci-status` on the run that started last at the head. A re-triggered workflow leaves an older red `ci-status` run beside the newer green one (the check-runs `filter=latest` read keeps one per check suite), and the gate refused a green pull request on the stale failure. A newer run still pending waits. Runs that started at the same time, or any run with no readable start time, keep the old rule that any failure decides. Only GitHub Actions' `ci-status` runs are read, so another app's run of that name cannot outrank the real one with a later start time.
