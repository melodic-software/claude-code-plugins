---
bump: patch
---

### Changed

- The babysit merge gate reads pr-review-main's `verdict=none reason=chunk-failed` check run as a
  designed stop, like `too-large`, `binary` and `long-line`: it counts no CRITICAL finding and
  binds no lane.
