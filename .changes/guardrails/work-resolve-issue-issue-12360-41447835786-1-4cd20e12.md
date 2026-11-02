---
bump: patch
---

### Fixed

- `block-dangerous-git` now blocks a destructive git command placed after an array assignment or
  an extglob followed by `#`, such as `a=(x)#; git reset --hard`. The shared `hook-utils.sh` Bash
  command parser reads a `#` right after the `)` of `a=(…)` or `@(…)` as literal text, as Bash
  does, not as the start of a comment that hid the rest of the line.
