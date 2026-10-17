---
bump: patch
---

### Fixed

- `babysit-prs` post-merge check: a red full run now counts against a merge only for checks that were not already failing on the branch's newest completed run of the same event before the merge. A check is a failed job, or one hygiene gate the aggregator names in a titled annotation. The `ci-status` aggregator adds nothing beside another failed job, and the gitleaks gate, which scans every branch on schedule and dispatch runs, counts against no merge. A run with nothing left is listed under `unattributed` and verifies the merge like a green run. With no earlier run, every failing check still counts. A red run with no failed job counts as its own check. The demotion-alert workflow's one re-run under `github-actions[bot]` is judged like the wrapper's when the bot did not start the run, and the wrapper starts no re-run once attempt 2 exists.
