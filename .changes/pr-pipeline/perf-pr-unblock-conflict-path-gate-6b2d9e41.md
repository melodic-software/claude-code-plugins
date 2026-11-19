---
bump: patch
---

### Changed

- pr-unblock's resolve-conflicts lane sends a same-head retry after an unresolved-conflict stop only once main changes one of the paths that round left conflicted. The push job's check run now records the round's pinned base and unmerged paths. The dispatcher compares that base with main's tip in one call and skips the head while no commit since touches those paths. A missing record, a failed read, or a new head sends as before.
