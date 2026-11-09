---
bump: patch
---

### Fixed

- The pre-push content check and the reference check no longer refuse a push when the working tree holds a file named like a pushed commit SHA: their `git rev-list` and `git diff` calls now separate revisions from paths with `--`.
