---
bump: minor
---

### Added

- `limits.api.<pool>.limit-cap` sets the requests per window a GitHub API pool plans to: planned = min(header limit, `limit-cap`), used = header limit - header remaining, left = planned - used. `github-token` defaults it to 1000, GitHub's documented GITHUB_TOKEN limit of 1,000 requests per hour per repository, so an observed 5,000 header limit is headroom, never a target; the other pools have no cap. The rate guard's read floor is now a share of the planned budget, in the Node guard (`planOf` in `.github/actions/log-api-budget/rate-guard.mjs`) and in the shell guard (`API_BUDGET_LIMIT_CAP`, which ci-status sets to 1000). The stop still reads only the header's remaining and GitHub's 403 and 429 refusals, and `writer-pause` and `breaker` stay shares of the header's limit.
