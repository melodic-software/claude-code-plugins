---
bump: minor
---

### Added

- `noise-report.py --baseline <before.json> [--margin M]` compares two results of the same suite, paired by case name: the with-arm change with its interval, the without-arm change as a drift check, each case that fell by a third or more, and a non-inferiority verdict at the margin. `/evals:plugin-eval` reads it beside the noise report's other lines.
