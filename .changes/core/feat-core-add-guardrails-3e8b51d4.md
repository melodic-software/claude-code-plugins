---
bump: minor
---

### Changed

- `core` now also installs `guardrails`, so a standalone `core` install gets the guard hooks that block secret leaks and destructive commands such as `git reset --hard`, force pushes and unguarded recursive deletes.
