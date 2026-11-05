---
bump: patch
---

### Changed

- The rewrite guide's self-audit is one pass, without the second read

  The self-audit pass that applies the judgment rows to unflagged
  sentences stays; the extra read after it is gone, since Opus 5 checks
  its own work without being told to.
