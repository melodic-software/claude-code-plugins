---
bump: major
---

### Removed

- **Breaking:** `pr-pipeline.schema.json` no longer admits `limits.api.<pool>.limit-cap`, so a `pr-pipeline.yaml` that sets it fails validation; delete it. Every pool's read floor is a share of its live `x-ratelimit-limit` header, so GITHUB_TOKEN no longer plans to a 1,000-request budget, and ci-status's `API_BUDGET_LIMIT_CAP` and `BABYSIT_READ_FLOOR_HEADER_LIMIT` are gone ([#18194](https://github.com/melodic-software/claude-code-plugins/issues/18194)).
