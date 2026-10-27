---
bump: patch
---

### Fixed

- work-unblock re-fires an issue run whose broker-check `Ask the broker whether the lane may run` step failed for any reason but the lanes kill switch, or with no reason its log names, as a failed mint ([#9102](https://github.com/melodic-software/claude-code-plugins/issues/9102)). The read runner work-resolve-issue calls has no `Request the lane token` step, so such a run matched no no-work class and, past its one re-fire per version of the lane workflow files, waited on the stranded backoff. It now waits `limits.reset-clamp-min` hours after the run ended and is re-fired up to `limits.limit-stops-per-issue` times per version of those files, then on the stranded backoff, like a failed `Request the lane token` step. A kill-switch refusal there stays a breaker trip. The failed-mint backoff record now says the run could not get its lane token or the token broker's leave to run (`.github/scripts/work-unblock/label-unblocked.mjs`).
