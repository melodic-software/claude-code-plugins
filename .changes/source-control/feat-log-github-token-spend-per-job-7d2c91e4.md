---
bump: patch
---

### Changed

- The babysit scripts' gh seam (`babysit_gh._run_gh`) records rate-limit readings from its own `gh api` responses when the job names the token. That needs `API_BUDGET_TOKEN` (or `API_BUDGET_OVERRIDE_TOKEN`, for a call that carries its own `GH_TOKEN`) and `RUNNER_TEMP`. The call then runs with `-i`, and each response's `x-ratelimit-*` headers become one line in `$RUNNER_TEMP/api-budget/<token>`. The caller still gets the output it would have had without `-i`. With those variables unset, nothing changes.
