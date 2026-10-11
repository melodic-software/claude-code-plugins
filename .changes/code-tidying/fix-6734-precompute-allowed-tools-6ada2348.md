---
bump: patch
---

### Fixed

- `tidy`: dropped the trailing `; :` from the open-PR-count pre-compute line, which matched no `allowed-tools` grant and ended a `--permission-mode dontAsk` run at zero turns.
