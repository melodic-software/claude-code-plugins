---
bump: patch
---

### Changed

- The interview page's `round.sh` now gives each outcome its own exit code: 1 for a refusal (a usage error included, which used to exit 2), 2 for a missing prerequisite (Python 3, or curl for `ensure-running`, which used to exit 1 while `watch.sh` exited 2), 5 when `ensure-running` cannot start the page server, and 6 when `export-ledger --diff` or `ledger-check` finds the page and the ledger disagree, or a ledger merge keeps a conflicting row. `round.sh --help`, the interview skill and its page protocol list the codes.
