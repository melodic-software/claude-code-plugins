---
bump: patch
---

### Fixed

- The lane run report comment posts on the pull request again. The `report` job of both `pr-run-activity-read.yml` and `pr-run-activity-write.yml` now holds `pull-requests: write`, which GitHub required for `POST /repos/{repo}/issues/{pull}/comments` on a pull request when the job held `issues: write` alone (403 `Resource not accessible by integration`). Every job calling either runner grants `pull-requests: write`; the model jobs keep `pull-requests: read`.
