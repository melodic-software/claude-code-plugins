---
bump: major
---

### Changed

- **`/coupling:reduce` splits findings into an apply step and a route step.** "Lane" now means
  only a worker that serves one pipeline stage. The ledger field is `step: apply | route` (rename a
  `lane:` field to `step:`, with no alias).
