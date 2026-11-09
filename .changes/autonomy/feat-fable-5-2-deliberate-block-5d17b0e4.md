---
bump: patch
---

### Changed

- The autonomous-pipeline reminder adds a clause that stops recovery at anything put in the run's way on purpose (a protected path, a refused permission, a safety control): the run does not route around it, reports what blocked it, and reaches the goal by another permitted path. The README cites the Claude Fable 5.2 guide section it rests on.
