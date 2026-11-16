---
bump: patch
---

### Changed

- The bundled prerequisites checker honors an entry's optional `when` (`config_any`: file names, or a file and a pattern its text must match): the SessionStart probe stays silent about the entry unless one of those configs sits in the project directory or above it, and `check` reports it INFO there.
