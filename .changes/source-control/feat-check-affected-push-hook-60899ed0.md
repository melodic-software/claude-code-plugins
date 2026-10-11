---
bump: patch
---

### Changed

- The `ready` step runs `scripts/check-affected.sh --tests` on the merged head as its deterministic gate when the repository ships that script.
