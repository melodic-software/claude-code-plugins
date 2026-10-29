---
bump: minor
---

### Added

- `/source-control:babysit-prs` worker tier: the thread resolver takes `--own-pr-lane-logins`, filled from `babysit_lane_logins`. On a PR opened by your own login, `--autonomous` refuses the whole PR. With the flag, it resolves an outdated, bot-opened thread that a configured lane login other than the opener has already replied to. It still never resolves a CRITICAL or security thread, a thread a person opened, or a thread with a comment from your own login. Other threads report `skipped-own-pr-not-lane-answered`. The resolve runs under your existing login, so no permission is added.

### Fixed

- The resolver's own-PR refusal never fired. The resolver read the PR author's login from the wrong level of the `gh pr view --json author` payload and always got an empty login, so `--autonomous` treated every PR as someone else's. On your own PRs it could resolve an outdated bot thread you had replied to yourself. It now reads the login correctly, and it refuses when the author cannot be read. Without `--own-pr-lane-logins`, the worker now resolves nothing on your own PRs.
