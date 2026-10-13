---
bump: patch
---

### Fixed

- The always-loaded-set stats (`instruction-load-stats`) no longer count a path-scoped rule as always loaded when `grep -q` closes the pipe on the rule's frontmatter before the writer finishes, which made the token estimate jump and the test fail intermittently with `printf: write error: Broken pipe`.
