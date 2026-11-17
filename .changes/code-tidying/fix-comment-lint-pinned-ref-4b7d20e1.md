---
bump: patch
---

### Fixed

- The comment lint keeps the version comment trailing a `ref:` line pinned to a full commit id, as it already did for a pinned `uses:` line, so a re-pin that moves checkout refs no longer fails the lint.
