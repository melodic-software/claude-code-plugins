---
bump: patch
---

### Changed

- `/source-control:babysit-prs`: the merge hold floor lists `.github/scripts/lib/stop-reason.mjs`, which the issue lane's report-outcome now imports, as enforcement, so a pull request that changes it holds for a person as one changing report-outcome does.
