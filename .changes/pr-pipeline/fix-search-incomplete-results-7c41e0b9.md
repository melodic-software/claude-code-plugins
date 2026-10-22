---
bump: patch
---

### Fixed

- check-wip-cap treats a GitHub search answer with `incomplete_results: true` as unknown, not as a failed read: on or after `pause-from` new admissions pause with `admission_basis` and `admission_reason` `search-incomplete` and a `check-wip-cap` warning, so work-unblock defers newly unblocked issues instead of admitting without limit on a false empty. A read that fails without that answer still fails open, and no run pause changes.
