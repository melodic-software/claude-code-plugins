---
bump: minor
---

### Added

- `/performance:climb` takes an optional holdout harness, off by default. When given, it is a second command `/performance:snapshot` froze (its own `Frozen:` line with `discriminate: exit 0`), recorded in `holdout.json` beside `keep-rule.json`, stability-checked once in each worktree at the start, never run or read during attempts, and measured at the end on the start and last kept commits. The report gains a `Holdout:` line saying `held` or `did not hold` with both numbers, or `not run (nothing kept)`; the holdout informs and never reverts. With no holdout the run and report are unchanged. Two evals cover the off and on cases.
