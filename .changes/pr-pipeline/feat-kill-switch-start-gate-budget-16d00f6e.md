---
bump: minor
---

### Added

- `limits.api.github-token.start-gate`, a share of the header's `x-ratelimit-limit` (default 0.1, in `.github/actions/log-api-budget/rate-limits.json`). The kill-switch gate (`.github/actions/check-kill-switch`) now also stops a lane at its start while the GITHUB_TOKEN core pool's remaining is under that share and the reset is still ahead, from one GET /rate_limit with the job's token (its `x-ratelimit-*` headers, else the body's `resources.core`). The stop keeps `reason=kill-switch`; a new `cause` output says `switch`, `expiry`, `budget` or `ok`. A failed or unreadable read proceeds with a warning. Each switch variable also accepts `true@<UTC time>`, which stops until that time. work-unblock's sweep re-fires a budget-stopped issue run on its next sweep and never counts it toward `limits.limit-stops-per-issue`.
