---
bump: patch
---

### Fixed

- A work-resolve-issue run that `issue-prior` stops before any model turn because a trusted open PR already closes the issue is now reported on the issue. `issue-prior` skips `closed-by-open-pr` instead of `not-applicable`, the run job's `skip-reason` output carries it, and the read file's new `scan-skip-reason` output hands it to the caller once the scan job's decode step has checked it. `work-resolve-issue.yml` then runs `report-outcome` with `dimension-skip: closed-by-open-pr`, which reads the issue's open closing PRs itself and waits on the trusted one with an `outcome=wait pr=<n>` marker, so work-unblock leaves the issue alone until that PR merges or closes. When no trusted PR closes the issue any more, it posts nothing.
