---
bump: none
---

Test-only: `splice-assets.test.sh` reads `awk --version` through process substitution instead of piping it into `grep -q`; nothing that ships changes.
