---
bump: major
---

### Removed

- **Breaking:** `limits.admission-window-hours` is gone from the schema, so a `pr-pipeline.yaml`
  that still sets it fails validation; delete the key. `admission-window.mjs` is removed with it.

### Changed

- check-wip-cap is the one admission pacing gate. It counts queued work (open `agent-ready`
  issues with no hold label that no open lane PR names on its first body line, plus held lane
  PRs) against the queued cap, `max(limits.admission-factor × lane merges per hour,
  limits.admission-min-per-hour) × wip.merge-rate-window-hours`. At or over it, on or after
  `wip.pause-from`, new admissions pause: the action's new `admission-open` output is `false` and
  it logs `admission paused: reason=queued queued=... held=... cap=...`. Runs never pause on it.
- work-unblock admits at most the queued cap's room per run. A ready issue past it gets
  `admission-deferred`, and each hourly sweep revisits those issues oldest first, re-admitting only
  one whose newest `admission-deferred` the lanes App or a listed human added.
- The status JSON gains `queued_issues`, `queued_truncated`, `queued_total`, `queued_cap`, `admission_factor`,
  `admission_min_per_hour`, `queued_over`, `admission_open`, `admission_reason`,
  `admission_room` and `admission_basis`.
