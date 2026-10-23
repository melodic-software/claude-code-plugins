---
bump: patch
---

### Changed

- The babysit scripts' gh seam (`babysit_gh._run_gh`) records rate-limit readings from its own `gh api` responses when the job names the token. That needs `API_BUDGET_TOKEN` (or `API_BUDGET_OVERRIDE_TOKEN`, for a call that carries its own `GH_TOKEN`) and `RUNNER_TEMP`. A call that is not `--paginate` then runs with `-i`, and the leading header block's `x-ratelimit-*` values become one line in `$RUNNER_TEMP/api-budget/<token>`. The rest of stdout comes back byte for byte, so the caller gets the output it would have had without `-i`. With those variables unset, nothing changes.
