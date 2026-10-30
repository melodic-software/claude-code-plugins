---
bump: minor
---

### Added

- The report jobs of `pr-run-activity-read.yml` and `pr-run-activity-write.yml` post one comment
  per lane run on the PR, edited in place on a re-run, listing the activity, its outcome, the
  commits pushed and each GitHub API call the run job's scripts saw fail, by path and status.
