---
bump: none
---

Test-only: the audit-noise `detect.test.sh` reads git status through process substitution instead of piping it into `grep -q`; nothing that ships changes.
