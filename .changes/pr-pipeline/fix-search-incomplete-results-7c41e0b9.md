---
bump: patch
---

### Fixed

- check-wip-cap treats a GitHub search answer with `incomplete_results: true` as unknown, not as a failed read: new admissions pause whether or not `pause-from` is set or reached, with `admission_basis` and `admission_reason` `search-incomplete` and a `check-wip-cap` warning, so work-unblock defers newly unblocked issues instead of admitting without limit on a false empty. A read that fails without that answer still fails open, the queued cap still pauses only past `pause-from`, and no run pause changes.
- check-wip-cap's over-cap warning names why the lane keeps running (the base config could not be read, `pause-from` is not set, or `pause-from` not reached), and work-unblock's deferral log names its reason instead of always citing the queued cap.
