---
bump: patch
---

### Changed

- `plugin-eval` requires a detection control before a no-loss two-version compare ships a cut: the before text with the changed rule removed must score clearly lower on the same cases and model, else the reading is reported as unable to detect a loss.
- `design` asks, for a suite that will gate a cut, for cases that depend on each rule the cut touches, so that control can score lower.
