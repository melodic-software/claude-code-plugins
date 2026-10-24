---
bump: patch
---

### Fixed

- pr-merge's Dependabot gate now decides `ci-status` on the run that started last at the head. A re-triggered workflow leaves an older red `ci-status` run beside the newer green one (the check-runs `filter=latest` read keeps one per check suite), and the gate refused a green pull request on the stale failure. A newer run still pending waits, and runs with no start time keep the old rule that any failure decides.
