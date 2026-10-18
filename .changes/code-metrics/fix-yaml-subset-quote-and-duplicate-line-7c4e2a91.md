---
bump: patch
---

### Fixed

- The YAML subset reader no longer lets a quote inside a plain value hide a trailing comment: `title: it's fine # comment` now reads as `it's fine`. A quote opens a quoted string only where a value starts.
- A duplicate key inside a sequence-item mapping is now reported on the duplicate key's own line instead of the dash line.
