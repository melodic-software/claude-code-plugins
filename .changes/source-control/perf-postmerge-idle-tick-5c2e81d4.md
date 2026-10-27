---
bump: patch
---

### Changed

- `babysit_verify_evidence.py settle --idle-tick` lets pr-merge's post-merge-dispatch job reuse the post-merge report the last tick kept. The report must pass the lane room's reuse rule (`settle_shared`) and `babysit_postmerge.idle_refusal`. That rule takes a passing report only (exit 0 or 5) with no hold, no full run or re-run to start, no unattributed red run and no quarantine excuse, and at least 10 minutes left before `SHARED_MAX_AGE`. It also requires that since the report no verifying run completed, no quarantine issue changed, and every pin the check read reads the same again. The post-merge report now records those pins (`pins`).
- `pending_runs_unchanged` lists runs once for each verifying workflow instead of once for every workflow on the branch. On main, the all-workflow listing held 152 runs in under two hours, more than fit on one page.
- The reuse rule (`shared_refusal`) refuses a report once a quarantine excuse it carries has expired (`excuse-expired`).
