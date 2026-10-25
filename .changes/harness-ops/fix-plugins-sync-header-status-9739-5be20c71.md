---
bump: patch
---

### Fixed

- `/harness-ops:plugins` reads `needs update` in a marketplace's report header only for refresh, update and failure state. Work left to a person (an install declined, skipped by policy or held for the `ask` prompt, an unfilled or project-scope enable, an install left not enabled, a delisted plugin, a withheld downgrade) is counted as `, N action(s) pending` after the status, so an `install_new: none` run whose only gap is an uninstalled catalog plugin reads `current, 1 action(s) pending`. Each pending action still has its `Action needed` bullet.
