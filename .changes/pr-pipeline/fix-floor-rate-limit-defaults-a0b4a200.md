---
bump: patch
---

### Changed

- The `limits.api` defaults (each pool's `plan`, `writer-pause`, `breaker`, `read-floor`, github-token's `limit-cap`, content-creation's `per-minute` and `per-hour`) moved out of `pr-pipeline.schema.json` into [`.github/actions/log-api-budget/rate-limits.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/log-api-budget/rate-limits.json), their only copy, with the same values. The schema states no default for them now. The merge path floor (`merge-holds.mjs` `HOLD_PATH_FLOOR`, `babysit_risk.HIGH_FLOOR`, ci-status's `hold_patterns` and both review lanes' `hold-paths`) holds that file, so a change to a rate-limit default waits for a person, while a schema change does not.
