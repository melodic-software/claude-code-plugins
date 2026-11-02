---
bump: patch
---

### Fixed

- **`/harness-ops:morning-brief` no longer publishes its status page on a team layer's say-so.** A `medium: artifact` or `hosted` in the repository's tracked `.claude/rendered-views.md`, which any checked-out branch can write, now keeps the page in a local file and says why. The same value from `~/.claude/rendered-views.md` or an untracked, gitignored overlay still publishes.
