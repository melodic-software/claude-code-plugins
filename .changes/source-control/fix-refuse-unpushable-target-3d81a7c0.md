---
bump: patch
---

### Fixed

- `target-repo.sh` takes `--write`, which the create, ready and merge phases pass: it refuses with exit 1 a resolved repository GitHub reports you cannot push to, so a clone of someone else's public repository never receives your pull request or ready flip. An absent `permissions` field passes, and read-only callers (logs, annotations, polling) are unchanged.
