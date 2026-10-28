---
bump: none
---

Test-only: the `AffectedSuites` fixture ignores the machine's global and system git config, so its `git commit` no longer fails when `commit.gpgsign` is on and signing cannot reach its key; nothing a user runs changes.
