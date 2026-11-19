---
bump: minor
---

### Changed

- `block-lane-pr-disable-auto` reads the lanes App login from the new `block_lane_pr_disable_auto_app` option instead of naming one publisher's App. Unset, the default, the guard blocks every auto-merge disable, since it cannot tell which App is the lanes App: set the option, or turn the guard off with `block_lane_pr_disable_auto_enabled`.
