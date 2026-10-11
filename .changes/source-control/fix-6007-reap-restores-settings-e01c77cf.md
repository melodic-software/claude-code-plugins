---
bump: patch
---

### Fixed

- The worktree cleanup reap no longer leaves the worktree's tracked `.claude/settings.json` as the plugin uninstall CLI rewrote it: when the file was tracked and unmodified before the pass, the reap helper restores it from version control and names it, so plain worktree removal succeeds (#6007).
