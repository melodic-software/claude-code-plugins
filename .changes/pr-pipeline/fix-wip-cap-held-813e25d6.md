---
bump: minor
---

### Added

- A new optional `wip` block derives the issue lane's WIP cap from the lane merge rate: merged
  lanes-App pull requests per hour over `merge-rate-window-hours` (24) times
  `target-lead-time-hours` (2), rounded up, at least `min-cap` (default 1; this repository sets
  12, the earlier fixed cap); `limits.wip-cap` applies only when the merged count cannot be read.
  Held lane pull requests (`needs-human`, `do-not-merge`, or a body line exactly `Hold: a human
  merges this`) no longer count against it and form their own buffer, `held-cap` (60), with an
  alarm past `held-alarm-hours` (24). Lane PRs opened in the window may be at most
  `opened-to-merged-ratio` (0.8) of those merged. Over a cap the check alerts, and pauses the lane
  only on or after `pause-from` (empty: never). The check publishes its status as the `wip` step
  output, the step summary and its log line (README, WIP cap). `version` stays 2.
