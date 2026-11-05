---
bump: patch
---

### Changed

- shape drops the first-line and last-line re-read from its pre-send check

  Rules 1, 3 and 5 already state what the first and last lines carry, and
  Opus 5 checks its own reply without being told to.
