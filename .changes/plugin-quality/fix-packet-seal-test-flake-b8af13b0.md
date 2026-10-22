---
bump: patch
---

### Fixed

- The `packet-seal.sh` contract suite no longer fails at random on `sealed-at=` lines: its exact-line check now reads a here-string instead of a pipe into `grep -q`, which could exit before `printf` finished writing and fail the pipeline under `pipefail`.
