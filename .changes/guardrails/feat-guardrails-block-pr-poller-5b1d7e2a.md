---
bump: minor
---

### Added

- `block-pr-poller` denies a Monitor command, or a background Bash command, that loops, sleeps and polls a pull request (`gh pr view`, `gh pr checks`, `gh pr status`, or `gh api` on its pulls, check runs, statuses, artifacts or comments). The reason names `/source-control:pull-request monitor` and `gh event listen` on the pull request. The monitor skill's `monitor-poll.sh` passes. Kill switch: `block_pr_poller_enabled`.
