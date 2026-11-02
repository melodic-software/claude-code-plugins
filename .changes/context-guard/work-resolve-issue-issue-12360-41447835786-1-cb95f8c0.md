---
bump: patch
---

### Fixed

- The shared `hook-utils.sh` Bash command parser reads a `#` right after the `)` of an array
  assignment `a=(x)` or an extglob `@(x)` as literal text, as Bash does, not as the start of a
  comment.
