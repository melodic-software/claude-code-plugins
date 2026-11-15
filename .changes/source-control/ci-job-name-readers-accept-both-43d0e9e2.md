---
bump: patch
---

### Changed

- The babysit merge gate and its review-evidence and lane-run reads also accept the planned job
  names `Check Kill Switch` and `Publish Review` (`PR Review / Publish Review`,
  `PR Review Security / Publish Review`, under the caller's display name or id) beside the current
  ones, so runs under either name keep counting once the review lanes rename those jobs. The
  pull-request skill's merge-after-AI-review check accepts the `Publish Review` names too.
