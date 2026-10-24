---
bump: minor
---

### Changed

- `/work-items:work` and `/work-items:ship run` (per-item PRs) read the item's human-merge hold before `/source-control:pull-request create --pushed` and pass its `Hold:` line as `--hold`, so the PR opens with it before any flip, and no longer dispatch their own `ready --unattended`: `create --pushed` now runs `ready` itself when `pr_open_state` resolves `ready`. An unreadable hold, or project instructions that reserve the ready flip for a person, pass `--draft`. The evals are updated to match.
