---
bump: patch
---

### Fixed

- `merge-readiness.sh` now refuses a merge (`BLOCKED verify-fail`) at a head pr-verify failed when no PASS or PASS-NOTES was judged after the FAIL, instead of letting it through after the 30-minute no-verdict wait. An approving review of the head by a person on the trusted-actor list lifts it, as the merge queue does. A head with no verdict keeps the 30-minute wait.
