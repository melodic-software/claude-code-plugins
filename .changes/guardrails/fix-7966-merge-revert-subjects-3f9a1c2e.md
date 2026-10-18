---
bump: patch
---

### Fixed

- The commit-msg convention hook now lets the subjects git writes itself pass: `Merge ...` from `git merge` and `Revert "..."` from `git revert`. Every other subject is still checked against the team pattern.
