---
bump: patch
---

### Fixed

- `retro` session mode reads the score history with one Read tool call of its own and treats a missing file or a denied read as no history, instead of checking that the file exists through Bash. A `claude plugin eval` run no longer reads INVALID because the sandbox denied a chained `ls` of the plugin's data directory.
