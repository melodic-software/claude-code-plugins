---
bump: minor
---

### Added

- The kill-switch gate (`.github/actions/check-kill-switch`) takes a `budget` input. On a gate that starts new work (`budget: "true"`), it stops the lane while the GITHUB_TOKEN core pool's remaining is under github-token's `start-gate` share (0.1, read from `.github/actions/log-api-budget/rate-limits.json` alone) and the reset is still ahead, from one GET /rate_limit with the job's token: its `x-ratelimit-*` headers, else the body's `resources.core`. A gate that finishes or judges existing work keeps the default, switches only. The stop keeps `reason=kill-switch`. New outputs: `cause` (`switch`, `budget` or `ok`) and `reset`. A failed or unreadable read proceeds with a warning. work-unblock's sweep re-fires a budget-stopped issue run once the window's reset has passed, and never counts it toward `limits.limit-stops-per-issue`.
