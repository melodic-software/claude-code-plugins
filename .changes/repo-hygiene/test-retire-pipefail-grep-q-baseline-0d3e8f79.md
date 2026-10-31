---
bump: none
---

Test-only: `git-branch-audit.test.sh` reads the `find` listing through process substitution instead of piping it into `grep -q`; nothing that ships changes.
