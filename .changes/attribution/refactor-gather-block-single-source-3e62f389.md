---
bump: patch
---

### Changed

- `/attribution:audit` no longer gather repository context that no step read.
- `/attribution:setup` keeps its root-then-home resolution in order, since each call takes the value the one before it returned, under a renamed heading.
