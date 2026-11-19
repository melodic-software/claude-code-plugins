---
bump: patch
---

### Fixed

- `/source-control:worktree create` resolves `worktree.baseRef` one settings file per call: it reads the project `.claude/settings.json` first, skips `.claude/settings.local.json` without attempting it when a `Read` deny rule there covers it, and reads `~/.claude/settings.json` only when neither project layer sets the key. Agents had been reading all three files in one `grep`, which a project `Read(./.claude/settings.local.json)` deny rule refused as a whole. The `worktree-create-routes-through-helper` eval now seeds that deny and fails a run that reads the local file.
