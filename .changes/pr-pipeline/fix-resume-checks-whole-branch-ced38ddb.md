---
bump: patch
---

### Fixed

- A resumed `work-resolve-issue` run that reports done with no commit of its own now opens its PR from the branch it resumed instead of stopping for a person. `run-checks` runs the activity's checks over that whole branch, and `report-outcome` opens the PR only when at least one check ran and none failed, the branch is still at the tip checked, and every commit on it ahead of the default branch is the lanes App's. The PR body's Verification section records this; otherwise the run still hands back.
