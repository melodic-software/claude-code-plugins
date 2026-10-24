---
bump: minor
---

### Added

- `limits.api` sets GitHub API margins per pool (`github-token`, `lanes-app`, `graphql`, `owner-token`, `content-creation`), each a share of the limit the pool's `x-ratelimit-limit` header reports: `plan` (0.7), `writer-pause` (0.4), `breaker` (0.2) and `read-floor` (0.1); `content-creation` adds `per-minute` (80) and `per-hour` (500). The defaults live only in the schema. The rate guard reads only `read-floor`; the other fields are thresholds meant for the hub's limits sampler, not enforced here. resolve-config passes the block through as set.

### Changed

- Every lane GitHub call made through createGitHub, the dispatchers' budgetedFetch or the ci-status gh wrapper goes through one rate guard (`.github/actions/log-api-budget/rate-guard.mjs` and its shell port in `api-budget.bash`). A response that shows a pool exhausted (remaining 0, any 429, a 403 naming a rate limit or abuse detection, retry-after, or a GraphQL answer of any status with a `RATE_LIMITED` error or an error naming a rate limit) stops that pool, or every pool for a secondary limit or a 429, until its reset for the rest of the job: later calls are refused without a request, the call that hit it fails, and a Node step fails red with an error naming the reset. With no usable reset header, a secondary limit stops for a minute and any other limit for an hour; a paginated `gh api` call, whose headers the wrapper cannot see, gets the same from its error text. Under `read-floor` left it warns once and calls continue. ci-status's gh_read no longer sends a probe request while limited, and waits only for a reset a header gave, never a guessed one. A rate limit on check-born-triaged's read sets its new `rate-limited` output, which stops intake-triage and the needs-triage label. The check-born-triaged read, post-statuses and the maintenance, branch-cleanup and post-merge-demotion-alert scripts' raw API calls go through it too.
- intake-label-needs-triage reads the org and repository kill switches, as intake-triage does; either one stops its API reads and its label.
