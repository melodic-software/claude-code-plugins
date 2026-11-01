---
bump: minor
---

### Added

- `/work-items:decompose`: the base-commit check now offers a third choice for a criterion that already passes at the base commit: keep it, with a one-line reason. The published Done when writes that reason beside the check, so whoever picks the item up sees why a check that cannot fail at the starting commit is there (#11876).
