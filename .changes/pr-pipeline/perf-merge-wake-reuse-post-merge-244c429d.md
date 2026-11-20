---
bump: patch
---

### Changed

- On a `pr-merge.yml` run with no Dispatch Post Merge Runs job (a `pull_request_target` wake), the Merge job reads the last sweep's post-merge report and reuses it under the rule Enable Auto Merge's wake already uses (a passing check that `settle --idle-tick` keeps, `SHARED_MAX_AGE` unchanged), now in one script both jobs call, `.github/scripts/pr-merge/settle-last-report.sh`. Merge runs the post-merge check only when that rule refuses the report, the read fails, or settle passes 60 seconds. Scheduled and hand-started sweeps are unchanged (owner decision Q258, #17696).
