---
bump: patch
---

### Fixed

- set the lane comment legacy cutoff

  The review lanes write run bindings since ci-workflows#1071 merged
  (2026-11-11T22:24:32Z). LEGACY_CUTOFF is now 48 hours later,
  2026-11-13T22:24:32Z, in both ports: a lane comment with no binding counts
  only when posted at or before it and never edited. The 48 hours cover a run
  that resolved the reusable before the merge, and a re-run of one within the
  lost-run reconciler's 24-hour lookback.

  The clear-escalations test of an edited hold with no binding now expects
  it to read as no lane's; fixtures for unbound lane comments carry dates
  before the cutoff.
