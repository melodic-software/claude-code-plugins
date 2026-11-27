---
bump: patch
---

### Fixed

- Shared `check-lib.sh` synced where this plugin carries it: `checks_files` leaves out an exact rename (the same blob and mode under a new path), so a pure move is no longer formatted or linted as a changed file. `checks_files --include-exact-renames` keeps the full list, which the guardrails secret and path scan uses. A rename with an edit or a mode change is still listed and judged on its added lines only; a copy, an add and a modify are listed as before.
