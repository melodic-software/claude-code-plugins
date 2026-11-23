---
bump: patch
---

### Fixed

- The comment lint no longer judges a moved comment as new: an added comment line whose trimmed text the same change deletes elsewhere, in any file (a block moved between files, or re-indented), is not judged. A moved comment that is reworded, and a new comment beside it, are still judged. In a merge commit, a line deleted against any parent counts.
