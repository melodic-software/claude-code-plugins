---
bump: patch
---

### Fixed

- `pull-request` `ci --ci` (fix-ci) now states that every context-file `path` and every edited file is relative to the pull request's checkout, never this skill's own directory, so an agent no longer aims a fix at the loaded plugin copy when the same relative path exists in both.
