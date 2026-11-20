---
bump: minor
---

### Changed

- `block-lane-pr-disable-auto` reads the lanes App login from the new `block_lane_pr_disable_auto_app` option instead of naming one publisher's App. Unset, the default, the guard blocks a disable on any pull request a GitHub App opened (`app/<slug>` or `<slug>[bot]`), since it cannot tell which App is the lanes App; a pull request a person opened passes, and one whose author cannot be read stays blocked.
