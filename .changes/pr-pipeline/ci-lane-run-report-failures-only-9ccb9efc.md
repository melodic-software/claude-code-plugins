---
bump: minor
---

### Changed

- The lane run report posts a pull request comment only for a run that failed or was cancelled (a designed skip counts as clean) or recorded a failed GitHub API call, one comment per workflow run (`<!-- lane-run-report run=<run id> -->`) with a section per failed activity. A clean run writes the report to the job summary only. Comments under the old per-activity marker are left as they are.
