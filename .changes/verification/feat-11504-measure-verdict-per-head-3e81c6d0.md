---
bump: minor
---

### Added

- `/verification:measure` records its `compare` verdict and the improvement claim it judged for
  the head commit it measured, through `scripts/confirm-verdict.sh record --of measure`, so the
  pull request `ready` report can name it. With no baseline captured before the change the
  recorded verdict is `CANNOT QUANTIFY`. A commit after the record leaves the new head with no
  verdict.
