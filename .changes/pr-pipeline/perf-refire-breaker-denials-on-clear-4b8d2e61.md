---
bump: patch
---

### Changed

- work-unblock re-fires an issue run that the lanes kill switch stopped at broker-check on the first hourly sweep after the switch clears, instead of waiting `limits.reset-clamp-min` hours after the run ended. That run ran no model, and the sweep runs only with the switch off. A trip at a post-model `Request the lane token` step still waits the clamp. The trip count, the stranded backoff past `limits.limit-stops-per-issue`, the WIP cap pause and `limits.restarts-per-run` are unchanged (`.github/scripts/work-unblock/label-unblocked.mjs`).
