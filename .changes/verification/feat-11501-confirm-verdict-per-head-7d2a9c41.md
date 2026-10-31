---
bump: minor
---

### Added

- `/verification:confirm` records its verdict and each `MISSING` or `PARTIAL` plan item for the
  head commit it judged, through the new `scripts/confirm-verdict.sh`, so the pull request `ready`
  report can name it. A commit after the record leaves the new head with no verdict.
