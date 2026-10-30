---
bump: patch
---

### Fixed

- `address-feedback` now works a review thread a trusted person with write access opened when
  that person's own `PR-fix lane: please fix this finding` line is in it. Before, a fix request
  counted only as a reply on a thread a review bot opened, so a maintainer could not ask the lane
  to fix a failing check on a PR no review bot commented on, and the lane stopped with
  `feedback-untaken-threads`. A thread an account off the trusted-actor list opened, one a person
  without write access opened, or one with no fix request is still left alone.
