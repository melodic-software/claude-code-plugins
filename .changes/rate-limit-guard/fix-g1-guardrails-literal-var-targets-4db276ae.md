---
bump: patch
---

### Changed

- Shared hook library: the Bash command parser also reports each redirect operand as written, quotes and escapes included (`HOOK_SEG_REDIR_RAW`). No hook in this plugin changes behavior.
