---
bump: patch
---

### Fixed

- `/source-control:worktree create` on a `fresh` base no longer leaves the new branch tracking `origin/<default>`: the helper passes `--no-track`, so the first `push-branch.sh` run sets `origin/<branch>`. `create.md` names `git branch --unset-upstream` as the repair for branches created before this fix.
- The create block now runs to completion under zsh and leaves no temp files: `worktree-create.sh --remove-input-files` deletes the two rendered input files and their directory on every exit, so the block is the bare helper call with no `status=$?` and no `rm`.
- `worktree-create.sh` exits 4 with `cannot load <lib>` when `worktree-root-resolve.sh` or `hooks/worktree-path-lib.sh` is missing, instead of failing later with an unrelated git error.
- `create.md` says what to do when a settings file holding `worktree.baseRef` cannot be read: name the layer, assume `fresh`, and ask, or state the assumption when no user is present.
