---
bump: patch
---

### Fixed

- `/work-items:work` CI mode no longer stops on a check the issue names as a PR or CI check: when the run cannot run it, it records it in `not_done` as left to the PR's CI with `"required": false`, so the issue lane opens the PR instead of handing the issue back.
