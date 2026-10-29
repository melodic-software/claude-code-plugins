---
bump: patch
---

### Fixed

- A pull request no longer stays red on a stale `ci-status` after the pr-unblock lane that stopped on its head clears its own `pr-unblock/*` status. A status post starts no run, so the next `maintenance-reconcile-lost-runs` run re-runs, once and recorded so `pr-verify` trusts it, the failed `ci-status` of a newest `pr-require-checks` run whose first attempt failed only on pr-unblock stops, once no such status fails the head. A failed re-run is a warning, not a failed reconciler run.
