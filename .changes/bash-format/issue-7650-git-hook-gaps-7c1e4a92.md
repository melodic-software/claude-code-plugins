---
bump: patch
---

### Fixed

- The shared git-hook check library reads the range diff with `--text`, so a tracked `-diff` attribute no longer hides a text file's added lines from a check.
