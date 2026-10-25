---
bump: patch
---

### Fixed

- The babysit scripts stop calling GitHub once a rate-limit pool is exhausted. A response with `x-ratelimit-remaining: 0`, a `retry-after`, any 429, a 403 naming a rate limit or abuse detection, a GraphQL error message naming one on any status, or a GraphQL `RATE_LIMITED` error latches that pool (every pool, for a secondary limit): no later call to it is sent before its reset, and the process exits red with one `::error` naming the pool and the reset. Below a pool's `writer-pause` share no write is sent, and below its `read-floor` share the report-only FAIL summary quote in a verifier escalation is skipped. The shares are `limits.api` in `docs/conventions/pr-pipeline.yaml`; a block present but unreadable refuses every call, and with no such file (an installed plugin, a consumer repository) only the signals latch, with no margins (`babysit_gh.py`). In a GitHub Actions job each stop is also appended to the job's stop file (`$RUNNER_TEMP/api-budget/stop`, lines `<pool> <reset epoch>`) that the lanes' JavaScript guard and gh wrapper share, and a stop recorded there by any earlier step or process refuses its pool (every pool, for `*`) until its reset, so the next process sends nothing either.
