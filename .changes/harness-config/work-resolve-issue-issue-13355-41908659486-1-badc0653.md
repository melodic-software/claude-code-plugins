---
bump: patch
---

### Fixed

- `audit-permission-grants` now scans the main checkout's `.claude/settings.local.json` when run in a linked worktree, and a subdirectory's `.claude/settings.json` when run from that subdirectory.
- `audit-automation-gaps` inventory reads the same files: the start directory's `.claude/settings.json`, and the main checkout's `.claude/settings.local.json` in a linked worktree.
- The effort-pin drift check hashes the defaults list item without its list number, so renumbering the list no longer reports the table `changed`.
