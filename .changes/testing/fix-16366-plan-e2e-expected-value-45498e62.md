---
bump: patch
---

### Fixed

- `/testing:plan` asks each planned test's entry to name its expected-value source per `testing:test-value`, where the entries are written, and suggests `/testing:run-e2e` for an API endpoint change even when no served app exists.
