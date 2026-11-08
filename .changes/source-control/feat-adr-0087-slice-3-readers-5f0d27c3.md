---
bump: patch
---

### Changed

- The `--merge` gate's review evidence reads a usage-limit failure from the lane-outcome record in a review check's failure annotation (its `class` is `rate-limit`) or from the lane's own `failure-class=rate-limit` line, and no longer from the legacy `class=rate-limit` token alone.
