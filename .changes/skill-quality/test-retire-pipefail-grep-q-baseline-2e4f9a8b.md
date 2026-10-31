---
bump: none
---

Test-only: `check-skill.test.sh` reads the `--help` output through process substitution instead of piping it into `grep -q`; nothing that ships changes.
