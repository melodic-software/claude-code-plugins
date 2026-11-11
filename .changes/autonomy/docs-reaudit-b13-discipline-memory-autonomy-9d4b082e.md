---
bump: patch
---

### Changed

- The `setup` skill's Windows surface records and trigger adapters no longer restate Claude Code,
  Microsoft WSL, Docker Sandboxes, GitHub, routines and Slack documentation: each keeps the
  skill's own isolation or trigger rule and links the exact upstream sections to read live, with
  an as-of date and a recheck trigger naming what would make the rule wrong. No behavior change.
