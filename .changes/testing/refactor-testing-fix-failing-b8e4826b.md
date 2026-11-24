---
bump: major
---

### Changed

- The failing-test skill is invoked as `/testing:fix-failing`, with no alias: its name now says it fixes.

### Added

- `/testing:fix-failing diagnose` runs only the investigate phase and stops with the cause at file:line, its classification and the command that reproduces it, changing no code, the same meaning `diagnose` has in `/debugging:debug`.
