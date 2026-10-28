---
bump: minor
---

### Added

- **`schemas/attribution.schema.json`: the settings have a schema.** It describes the team layer `<home>/attribution.yaml`; the same keys are valid in `<home>/attribution.local.yaml` and the legacy `.claude/` JSON files. The keys are `excluded_paths`, `budgets`, `separation`, `stamp_expiry_days`, `trigger_less_stamp_check`, `judge_samples`, `gates` and `accuracy`, each optional and typed, and the schema rejects any other key, `accuracy.judge_samples` included. The audit itself still reads the files as before.
