---
bump: patch
---

### Fixed

- `/session-flow:audit-sessions` no longer marks `tokens.main` and `tokens.sub` lost when one message's streamed records differ on input or cache usage. The API's `message_delta` usage is cumulative, so later records of a message can carry higher input and cache counts, and the dedup that keeps each message's last record is still right. The `invariant:usage_split` canary, which counted any such difference, is replaced by `invariant:usage_regress`, which counts a message whose last record falls below an earlier one on input or cache usage, the case where keeping the last record would undercount. Collecting re-ingests every session, since the collector changed.

### Changed

- The `hooks.stop_ms` basis now says the metric reads every `hookInfos` entry and cannot tell a background (`async` or `asyncRewake`) Stop hook from a blocking one, so where such a hook has an entry the wait overstates the blocking cost.
