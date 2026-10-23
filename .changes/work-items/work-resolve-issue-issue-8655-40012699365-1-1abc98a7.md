---
bump: minor
---

### Changed

- `/work-items:work` and `/work-items:ship run` (per-item PRs) read the item's human-merge hold before `/source-control:pull-request create --pushed` and add its `Hold:` line right after the PR opens, and no longer dispatch their own `ready --unattended`: `create --pushed` now runs `ready` itself when `pr_open_state` resolves `ready`. An unreadable hold asks `create --pushed` for a draft. The evals are updated to match.
