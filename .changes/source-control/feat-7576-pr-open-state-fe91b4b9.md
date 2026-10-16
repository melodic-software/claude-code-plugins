---
bump: minor
---

### Changed

- `pr_open_state` now defaults to `ready`. `/source-control:pull-request create` always opens the PR as a draft and, when the state resolves to `ready`, runs `ready` on it, so a PR reaches ready only through `ready`'s base merge, reviews and verify gate; a gate that stops leaves it a draft and the report says why. A PR stays a draft only when the invocation asks for one (to show work early, or as a multi-session container), when a level sets `draft`, or when the run is unattended. A request for a draft wins over every configured level. `create` reference §2.4.3 states what a save point, a draft and a ready PR each mean.
