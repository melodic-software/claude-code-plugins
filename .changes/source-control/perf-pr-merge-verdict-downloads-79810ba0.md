---
bump: patch
---

### Changed

- The pr-merge gate fetches each verdict.json by the listed artifact's id (`GET .../actions/artifacts/{id}/zip`, one request) instead of `gh run download`, which first lists the run's artifacts (two requests). An artifact listed without an id still goes through `gh run download`. A verdict download refused for a rate limit (`babysit_gh.gh_rate_limited`) under `BABYSIT_VERIFY_GH_TOKEN` is made again with the process (lane) token and sets `read-token-limited` in `BABYSIT_RUN_CACHE`, which the review-evidence reads already honor, so the run's later downloads use the lane token too. Once the lane token is refused a download with a 401 or 403 that names no rate limit, `lane-download-refused` keeps the run's later downloads on `BABYSIT_VERIFY_GH_TOKEN`. Any other refusal is not retried. No gate decision changes. `babysit_util.run_command` and `babysit_gh.gh_capture` take `binary=True` to keep stdout as bytes; `READ_TOKEN_LIMITED` and `token_key` move to `babysit_run_cache`.
