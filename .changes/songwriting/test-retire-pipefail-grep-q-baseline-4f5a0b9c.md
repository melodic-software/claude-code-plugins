---
bump: none
---

Test-only: `datamuse.test.sh` reads `command -v curl` through process substitution instead of piping it into `grep -q`; nothing that ships changes.
