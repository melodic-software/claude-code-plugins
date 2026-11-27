---
bump: patch
---

### Fixed

- Shared `check-lib.sh` synced where this plugin carries it: `checks_files` leaves out an exact rename (the same blob and mode under a new path), so a pure move is no longer formatted or linted as a changed file. `checks_files --include-exact-renames` keeps the full list for checks whose verdict depends on a file's name or location: the guardrails content scan and reference verify, and the spelling lint. A rename with an edit or a mode change is still listed and judged on its added lines only; a copy, an add and a modify are listed as before.
- The lint entry passes `--include-exact-renames`: typos checks file names by default, so an exact rename to a misspelled name still fails the commit.
