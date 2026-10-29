---
bump: patch
---

### Changed

- The config reader now refuses a plain YAML value holding a colon and a space (such as `label: needs: triage`) and a plain key holding whitespace, `$` or `.` (such as `$schema: x` or `a.b: c`), naming the line. One such line now makes the whole file invalid, where the value used to be read as text or the key reported on its own. Quote the value or key to keep it.
