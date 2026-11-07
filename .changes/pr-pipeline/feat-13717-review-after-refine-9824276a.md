---
bump: minor
---

### Added

- The hosted review lanes wait for this head's Refine before reviewing: a `wait-refine` job waits
  up to 40 minutes for the `pr-refine` run this head's `pull_request_target` dispatcher started,
  skips the review when the head moved meanwhile (that push starts the new head's review), and
  reviews on every other outcome, a failed read included.
