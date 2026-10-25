---
bump: patch
---

### Fixed

- An issue's closing pull requests count only the open ones: GitHub lists a merged pull request in `closedByPullRequestsReferences` despite `includeClosedPrs: false`, so admission and the work-unblock sweep waited on a merged closer forever and find-prior stopped the issue lane for one (`.github/scripts/work-resolve-issue/report-outcome.mjs`).
