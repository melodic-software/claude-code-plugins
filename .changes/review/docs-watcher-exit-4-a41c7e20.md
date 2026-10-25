---
bump: patch
---

### Fixed

- `explain-change` says what to do when the view watcher exits 4 after its run of empty waits: re-arm it with the command it prints while the reader is still using the view.
