---
bump: none
---

### Fixed

- `ruff-format.test.sh` and `ruff-format-end-of-turn.test.sh` pass on Windows Git Bash. The first strips the CR a Windows `jq` adds to each line before reading the SessionStart row's arguments. Both run the spawn-budget case only where a working Linux `strace` is present, not the Cygwin one Git Bash ships.
