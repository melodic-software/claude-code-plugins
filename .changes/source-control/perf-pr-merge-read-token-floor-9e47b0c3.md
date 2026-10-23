---
bump: patch
---

### Changed

- The unattended merge gate reads its review evidence under `BABYSIT_VERIFY_GH_TOKEN` only while that token's core bucket has at least `merge.read-token-floor` of its limit left (`PipelineConfig.read_token_floor`, default 0.3, taken from the default branch head). Below the floor, or when `GET /rate_limit` cannot be read, the reads keep the process (lane) token and a `read-token-floor:` line goes to stderr. `babysit_whole_review._short_bucket` takes an optional `share` and `buckets`; whole-review requests keep `MIN_SHARE`.
