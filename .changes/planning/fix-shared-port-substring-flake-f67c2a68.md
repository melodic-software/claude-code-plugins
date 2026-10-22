---
bump: patch
---

### Fixed

- The shared-session test that a pending live entry's port never reaches a guest or leader no longer fails when a timestamp in the state happens to hold the port's digits: it now checks string values, keys and integers, not the raw JSON text.
