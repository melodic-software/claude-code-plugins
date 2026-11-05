---
bump: patch
---

### Changed

- The PR-prep verify gate counts a `/verification:confirm` `NOT VERIFIED` whose only cause is `verification: skipped (<level>)`, from the default branch's level, as clean, so a team that turns verification down does not stall PR creation.
