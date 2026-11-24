---
bump: patch
---

### Changed

- The `index-check` pre-commit entry checks whether a rules file or the index file is staged before it copies the instruction files out of the index, so a commit that touches neither copies nothing.
