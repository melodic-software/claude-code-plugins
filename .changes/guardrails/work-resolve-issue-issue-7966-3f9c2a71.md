---
bump: patch
---

### Fixed

- The commit-msg convention hook no longer rejects the subjects git writes itself: `Merge ...` from `git merge` and `Revert "..."` from `git revert` now pass before the team pattern check. Every other subject is still checked.
