---
bump: patch
---

### Fixed

- `read` spools each response into a directory made by its own `mktemp -d` call (honouring `$TMPDIR`) instead of the plugin data directory, carries the printed path as a literal so the `curl -o` target stays visible in the approval prompt, and removes the file and the directory on every exit path.
