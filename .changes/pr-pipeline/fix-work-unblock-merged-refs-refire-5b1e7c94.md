---
bump: patch
---

### Fixed

- work-unblock no longer re-fires a stranded or failed issue run while a merged pull request names
  the issue on a `Refs:` line after its newest decision or refinement comment. The check is
  admission's own (`mergedRefsAfter`), so a host-run session's pull request counts whoever opened it
  and wherever its `Refs:` line sits. A listed human's `**Decision recorded.**` comment after the
  merge lets the re-fire go ahead, and a failed read re-fires as before.
