---
bump: patch
---

### Fixed

- `/evals:methodology`: the "Rewrite this criterion" template now takes one threshold per block, each with its own `basis:`, and a `baseline-relative` block holds only a fraction of the current rate. An absolute bar such as zero misses is written relative too, so it can no longer ride on another target's basis.
