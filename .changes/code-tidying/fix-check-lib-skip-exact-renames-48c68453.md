---
bump: patch
---

### Fixed

- Shared `check-lib.sh` synced where this plugin carries it: `checks_files` leaves out an exact rename (the same blob and mode under a new path), so a pure move is no longer formatted, linted or scanned as a changed file. A rename with an edit or a mode change is still listed and judged on its added lines only; a copy, an add and a modify are listed as before.
