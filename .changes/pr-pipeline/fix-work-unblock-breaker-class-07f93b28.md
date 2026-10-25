---
bump: patch
---

### Fixed

- work-unblock tells a run the token broker refused for the lanes kill switch, at broker-check or at a lane token request, from other failures by reading the refused job's log (one per run, at most 1 MiB, only the failed step's last line). Such a breaker trip is re-fired an hour after it ended with a record of its own, and past `limits.limit-stops-per-issue` trips on the stranded backoff; it no longer spends the once-per-version re-fire, counts toward the failed-mint bound, or posts the "fault in the lanes" backoff comment. A refusal for another reason, or a log it cannot read, is classed as before (`.github/scripts/work-unblock/label-unblocked.mjs`).
