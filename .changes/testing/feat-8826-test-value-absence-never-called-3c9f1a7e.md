---
bump: minor
---

### Added

- `/testing:test-value` flags two judgment-only shapes: an absence check with no paired presence case (fix: add a case where another input produces the value; a test that already has one is kept), and assertions that never reach the subject (fix: assert what the subject returns or changes). Three eval cases cover them.
