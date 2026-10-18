---
bump: patch
---

### Changed

- The Node floor in the prerequisite check is now 22. Node 21.0 and 21.1 lack `import.meta.dirname` and the old 20.11 floor passed them; Node 20 and 21 are past end of life.
