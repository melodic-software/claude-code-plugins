---
bump: patch
---

### Changed

- **`/harness-config:audit-automation-gaps` reads the enforcement hierarchy from the shared enforcement ladder.** The skill carries a generated copy of the enforcement-ladder convention at `context/enforcement-ladder.md` and points at it instead of listing the levels inline. The ladder adds a `make-impossible` rung above compiler settings and a `canonical-helper` rung below the linters. A consuming repository's own order in its project instructions still overrides the default.
