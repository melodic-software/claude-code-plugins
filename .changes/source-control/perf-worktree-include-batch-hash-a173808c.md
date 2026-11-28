---
bump: patch
---

### Changed

- `worktree-include.sh diff` compares carried files against the main checkout with two batched `git hash-object` calls in place of one `cmp` per file, in the default diff and in the `--worktree-only` check of a worktree with no carried manifest. Rows and exit codes are unchanged; it falls back to `cmp` when the two repositories use different object formats or a file changes during the run.
