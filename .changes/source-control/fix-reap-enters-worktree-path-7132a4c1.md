---
bump: patch
---

### Fixed

- `reap-project-plugin-records.sh` enters `--worktree-path` itself instead of requiring the caller's working directory to match it, so `/source-control:worktree cleanup` can run the reap from a worktree-isolated session where `cd` does not persist. The cwd-equality refusal is replaced by a refusal of a main working tree (its `.git` is a directory, or git reports its git dir equal to its common dir, as for `git init --separate-git-dir`), checked before the directory change, so the main checkout's records stay out of reach (#7132).
