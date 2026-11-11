---
bump: minor
---

### Added

- `limits.api.<pool>.stop-floor`, a share of the header's `x-ratelimit-limit` (default 0.02 for every pool, in `.github/actions/log-api-budget/rate-limits.json`). The Node rate guard (`rate-guard.mjs`) now stops a pool when a response's `x-ratelimit-remaining` is at or under that share, as it does at 0: no further call to the pool goes out before the header's reset, the stop is recorded in the job's stop file for later steps, and the step holds under `API_BUDGET_HOLD`, else fails. Before, a response under the read floor only warned and calls continued until GitHub refused one. A response with no readable limit, remaining or future reset never stops on it. The check reads headers already returned, so it adds no API call.
