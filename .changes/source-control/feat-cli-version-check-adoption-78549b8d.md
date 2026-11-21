---
bump: patch
---

### Changed

- the shared prerequisites checker gains a latest-release mode

### Fixed

- `ready` no longer refuses on Windows when a pull request closes more than one issue: the hold check stripped no carriage return from the issue list, so every issue but the last failed to read.
