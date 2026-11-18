---
bump: minor
---

### Added

- The babysit scripts' gh seam sends a REST read of a commit's statuses under `BABYSIT_JOB_GH_TOKEN` when a job sets it (`babysit_gh.job_token_env`), so a job whose process and verdict-reader token is an App token without the Commit statuses permission reads them with its own `GITHUB_TOKEN`. Writes and every other read keep their token.

### Changed

- A call whose `GH_TOKEN` override equals the process's own `GH_TOKEN` is named to the rate guard as `API_BUDGET_TOKEN`, not `API_BUDGET_OVERRIDE_TOKEN`, so a verdict reader set to the process token budgets against that token's pool.
- The whole-review request reads the job bucket and the running jobs with `BABYSIT_JOB_GH_TOKEN` when it is set, else with `BABYSIT_VERIFY_GH_TOKEN` as before.
