---
bump: patch
---

### Fixed

- **The engine gate no longer denies a simple reader command that only quotes the engine file name.** `gh issue create --title '... hygiene.py ...'` and the other commands on a closed reader allowlist (`cat`, `head`, `tail`, `wc`, `grep`, `rg` without `--pre`, `git show`/`log`/`diff`/`grep` without `-c` or `-O`, `gh issue`/`pr`) now treat single-quoted and `$`/backtick-free double-quoted literals as data. A pipeline, `awk`, `sed`, any unquoted operator, and a word that resolves to the engine still gate. On Bash and PowerShell alike, a quoted word that is a link to the engine under any name now gates too. Refs #6242.
