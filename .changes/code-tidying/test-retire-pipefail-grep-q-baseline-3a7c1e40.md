---
bump: none
---

Test-only: `detect.test.sh` reads git status through process substitution instead of piping it into `grep -q`; nothing that ships changes.
