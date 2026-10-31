---
bump: none
---

Test-only: `emit-gate.test.sh` reads `shellcheck --help` through process substitution instead of piping it into `grep -q`; nothing that ships changes.
