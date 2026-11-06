---
bump: minor
---

### Added

- `/discovery:research`: the per-claim corroborator floor (`research_corroborators`, default 2) and the recency-gate windows (`research_recency_active_days`, `research_recency_standard_days`, `research_recency_guide_days`, defaults 14, 30 and 90 days) are settings, read from the plugin option and `docs/conventions/discovery.yaml`. With nothing set, research behaves as before.
