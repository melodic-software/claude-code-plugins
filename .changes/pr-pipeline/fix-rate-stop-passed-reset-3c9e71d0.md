---
bump: patch
---

### Fixed

- A rate limit whose header reset passes between the rate guard recording it and `rate_stop_from` reading it no longer turns into a guessed one-hour stop on every pool: the limit is over, so `retry_call --read` retries the read. Before, a reset a second away could fail the merge group's queued pull request read, which turned main's scheduled run red in `scripts/ci-queued-pr.test.sh`.
