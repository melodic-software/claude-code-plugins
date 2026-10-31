---
bump: none
---

Test-only: `contract.test.sh` and `turns-to-complete.test.sh` read the producer through process substitution instead of piping it into `grep -q`; nothing that ships changes.
