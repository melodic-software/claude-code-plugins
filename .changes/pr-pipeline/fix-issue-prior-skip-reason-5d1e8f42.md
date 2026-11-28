---
bump: patch
---

### Fixed

- A work-resolve-issue run that `issue-prior` stops before any model turn because a trusted open PR already closes the issue now skips `closed-by-open-pr` instead of `not-applicable`. The run job's `skip-reason` output carries it, where it used to drop `issue-prior`'s reason, and the read file's new `scan-skip-reason` output hands it to the caller once the scan job's decode step has checked it. Given `DIMENSION_SKIP=closed-by-open-pr`, `report-outcome` reads the issue's open closing PRs itself and waits on the trusted one with an `outcome=wait pr=<n>` marker, or posts nothing when none closes the issue any more.
