---
bump: patch
---

### Fixed

- A pr-merge or intake-triage run that the token broker refuses with reason `kill-switch` no longer
  ends red. The lane breaker turns the repository kill switch on after a queued run has read its
  variables, so the run's own kill-switch check passes and only the broker's live read stops it.
  `request-lane-token` takes a new `kill-switch-ok` input (`token` mode only): on that 403 it ends
  green with a `lane-token-stopped` notice, no token and `skip-reason` `kill-switch`. Every step in
  pr-merge's `merge` and `enable-auto-merge` jobs and intake-triage's `apply-verdict` and
  `apply-refinement` jobs that uses the token already runs only when the token is set, and
  intake-triage's `refine-select` now skips on apply-verdict's new `stopped` output. Any other
  denial, and every caller without the input, stays red; work-resolve-issue stays red because
  work-unblock re-fires its issue from the failed mint step. `version` stays 2.
