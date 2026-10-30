---
bump: patch
---

### Changed

- `/source-control:pull-request comments --ci` now says the mode may run `chmod -x` on a file
  whose executable bit the pull request added, when a finding asks to drop it.
