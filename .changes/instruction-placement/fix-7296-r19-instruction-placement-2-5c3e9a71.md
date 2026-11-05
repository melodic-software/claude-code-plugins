---
bump: patch
---

### Fixed

- `/instruction-placement:audit` reads its context files with the Read tool, one per call, instead of concatenating them through Bash `cat`.
