---
bump: patch
---

### Changed

- The SessionStart probe reports a missing `actionlint` only where git tracks a `.yml` or `.yaml` file under a `.github/workflows/` directory, at the repository root or below it, the files the lint entry checks.
