---
bump: patch
---

### Removed

- The unattended merge gate no longer reads its review evidence with the process (lane) token when `BABYSIT_VERIFY_GH_TOKEN` is short or rate limited: `_evidence_read_env`, `ReadTokenLimited`, the `read-token-limited` run-cache mark, `PipelineConfig.read_token_floor` and `babysit_gh.gh_rate_limited` are gone, and `babysit_whole_review._short_bucket` takes only `env` again. With the read token set, every evidence read uses it; a refused read, a rate limit included, raises once and the candidate holds with `evidence-missing`.
