---
bump: patch
---

### Changed

- `/source-control:babysit-prs`: the merge hold floor lists `.github/scripts/lib/stop-reason.mjs`, which the issue lane's report-outcome now imports, as enforcement, so a pull request that changes it holds for a person as one changing report-outcome does, and `.github/scripts/lib/done-evidence.mjs`, which now decides whether the lanes App's already-done close is trusted, as trust.
