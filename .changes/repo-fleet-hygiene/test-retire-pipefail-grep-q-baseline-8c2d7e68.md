---
bump: none
---

Test-only: `audit-fleet.test.sh` reads each report excerpt through process substitution instead of piping it into `grep -q` or `grep -m1`; nothing that ships changes.
