---
bump: minor
---

### Added

- A SessionStart notice names `/guardrails:setup apply install-git-hooks` once per session when this clone lacks a guardrails git-hook entry or holds a drifted one. A declined entry stays quiet, and the `git_hooks_notice_enabled` option (on by default) turns it off.
