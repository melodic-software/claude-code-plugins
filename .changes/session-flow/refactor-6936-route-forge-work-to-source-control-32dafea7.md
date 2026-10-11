---
bump: patch
---

### Changed

- `/session-flow:clean-stop` opens each pull request through `/source-control:pull-request create` with the linkage line passed in, and falls back to `git` and the forge's own tooling only when that would stop to ask or the plugin is absent, instead of preferring a direct `gh pr create`.
