---
bump: patch
---

### Changed

- `worktree-include.sh diff` compares carried files against the main checkout with two batched `git hash-object` calls in place of one `cmp` per file, so a worktree with no carried manifest is checked in a fraction of the time; output is unchanged.
