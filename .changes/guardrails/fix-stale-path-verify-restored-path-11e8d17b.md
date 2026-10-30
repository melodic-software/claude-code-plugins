---
bump: patch
---

### Fixed

- `reference-verify` pre-push entry: a push from a linked worktree no longer flags a cited path that history once deleted and the tree has again. Git exports `GIT_DIR` to the hook, which made the checks resolve the repository root to the cited file's folder; the checks now run with git's directory variables cleared and find the repository from the file.
