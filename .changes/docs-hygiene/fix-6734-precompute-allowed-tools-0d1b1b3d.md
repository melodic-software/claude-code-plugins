---
bump: patch
---

### Fixed

- `audit-derivability`: the pre-compute line now calls `uncommitted-md.sh` directly and the skill declares the `allowed-tools` grants for it and `echo`, so a `--permission-mode dontAsk` run no longer ends at zero turns.
