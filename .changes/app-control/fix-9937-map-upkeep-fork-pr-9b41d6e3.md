---
bump: patch
---

### Fixed

- `/app-control:map refresh` takes a listed pull request as the upkeep pull request only when it is from the repository itself. A fork's pull request on a same-named branch makes the outcome blocked and is named in the report, and the pass pushes nothing.
