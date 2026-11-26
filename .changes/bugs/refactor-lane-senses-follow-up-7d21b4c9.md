---
bump: patch
---

### Fixed

- A retired `lanes` key in `~/.claude/bugs.md` is no longer read; `/bugs:setup apply` now moves it
  as `areas`, and the old-file warning and `check` name it, so the focus areas are not lost.
