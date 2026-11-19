---
bump: patch
---

### Fixed

- `worktree-create.sh` checks out a repository whose `.gitattributes` routes paths through `filter=lfs` with `GIT_LFS_SKIP_SMUDGE=1`, so LFS paths arrive as pointer files instead of copies from the LFS store, and one stderr line names `git lfs pull` and `git lfs pull --include <paths>` for fetching the content.
