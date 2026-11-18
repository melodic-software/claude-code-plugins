---
bump: patch
---

### Fixed

- `/architecture:enforce-boundaries` adds no second check for a rule a build-time boundary already
  enforces in full, such as a package export map; it proves that boundary on an injected violation
  instead.
