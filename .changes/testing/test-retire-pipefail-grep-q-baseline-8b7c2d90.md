---
bump: none
---

Test-only: `cant-fail-scan.test.sh` reads the scan's findings through process substitution instead of piping them into `grep -m1`; nothing that ships changes.
