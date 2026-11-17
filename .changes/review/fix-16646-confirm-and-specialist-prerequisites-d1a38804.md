---
bump: minor
---

### Changed

- The `ecosystem-specialist` agent runs a record's `requires` probes before each command, after tool presence and an unmet single-condition `opt-in`, and reports an absent one as `skip (prerequisite missing: <name>)` with its hint, never PASS or FAIL. It never installs a declared prerequisite.
