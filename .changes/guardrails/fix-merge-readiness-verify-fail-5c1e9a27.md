---
bump: patch
---

### Fixed

- The merge guard now refuses a merge at a head pr-verify failed when no PASS or PASS-NOTES was judged after the FAIL, instead of letting it through after the 30-minute no-verdict wait. An approving review of the head by a person on the trusted-actor list lifts it, as the merge queue does.
