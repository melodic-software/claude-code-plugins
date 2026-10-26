---
bump: patch
---

### Fixed

- `/source-control:worktree status` outside a repository now runs its cross-repository block to completion under zsh and leaves no temp files: `worktree-discover.sh --remove-input-files` deletes the two rendered input files and their directory on every exit, so the block is the bare helper call with no `status=$?` (read-only in zsh) and no `rm` (which leaked the directory when denied).
