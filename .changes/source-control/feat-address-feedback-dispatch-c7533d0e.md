---
bump: patch
---

### Changed

- `/source-control:pull-request comments --ci` now tells the skill to record exactly one
  disposition for every kept thread: the reply job posts nothing when one is missing, and an
  `INCORRECT` thread, like `UNCERTAIN` and `VALID-defer`, stays open for a person (#7032).
