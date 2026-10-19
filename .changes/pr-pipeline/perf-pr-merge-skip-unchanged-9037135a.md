---
bump: minor
---

### Added

- `merge.skip-unchanged` (`max-minutes`, default 60; `max-skips`, default 3): the pr-merge workflow
  reports a candidate the last gating run refused on unchanged inputs with that refusal, marked
  `carried`, instead of gating it again, until the refusal is `max-minutes` old or has been skipped
  `max-skips` runs in a row. `0` in either turns it off. The `sweep-cost=` line gains `skipped=`, and the
  `pr-merge-summary` artifact gains `skipped`: its `candidates` stays the listed count and
  `budget_stop` counts only gated candidates as reached.
