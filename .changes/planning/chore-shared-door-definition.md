---
bump: patch
---

### Changed

- `/planning:design` reads the one-way and two-way door definition from a shared reference that `/review:merge-risk` also reads, so the two cannot drift apart. The door calls and what follows each are unchanged.
