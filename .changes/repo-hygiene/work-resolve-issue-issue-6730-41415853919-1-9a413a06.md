---
bump: patch
---

### Fixed

- The shared hook library's Bash segment parser (`hook::bash_parse_segments`) now passes each substitution in an unquoted here-doc body (`$(...)`, a backtick pair, `${...}`, `$[...]`) to its callback as segments of their own, because bash runs them. A body under a quoted delimiter is still skipped as data.
