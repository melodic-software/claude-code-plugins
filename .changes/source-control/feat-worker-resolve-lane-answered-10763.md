---
bump: minor
---

### Added

- `/source-control:babysit-prs` worker tier: the thread resolver takes `--own-pr-lane-logins`, filled from `babysit_lane_logins`. On a PR opened by your own login, `--autonomous` used to refuse the whole PR. With the flag it resolves an outdated, bot-opened thread that a configured lane login other than the opener has already replied to. It still never resolves a CRITICAL or security thread, a thread a person opened, or a thread with a comment from your own login. Other threads report `skipped-own-pr-not-lane-answered`. With the flag absent or empty, the refusal is unchanged. The resolve runs under your existing login, so no permission is added.
