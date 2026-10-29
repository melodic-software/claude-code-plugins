---
bump: patch
---

### Fixed

- `/evals:methodology`: the "Rewrite this criterion" answer is now a fill-in template with slots for quality (with the user need it serves), measure, trials, target and `basis:`. The `basis:` slot accepts a measured baseline, a prior result, a benchmark or expert review that the user supplied, or `baseline-relative`. The target must follow from that basis, so a target backed only by how severe a miss would be has no slot. When the user supplies no basis, the target is written relative to the current rate, never as a placeholder.
