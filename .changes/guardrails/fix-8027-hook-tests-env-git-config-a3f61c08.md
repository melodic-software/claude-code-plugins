---
bump: none
---

Only the git-hooks test scripts changed: each now clears env-supplied git config before it creates a repository, so a caller's core.hooksPath no longer reaches it. Nothing that ships changes.
