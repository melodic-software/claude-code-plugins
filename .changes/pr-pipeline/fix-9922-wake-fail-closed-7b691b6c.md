---
bump: patch
---

### Fixed

- `pr-verify.yml`'s `wake-pr-merge` and `pr-merge.yml`'s `wake-eval-released` now fail closed (warning and skipping dispatch, leaving arming to the scheduled sweep) when `AUTOMATION_LANES_APP_SENDER_ID` is unset or invalid, the pull request read fails, or the trusted-actor list cannot be read, preventing PR-scoped wakes that the lanes token broker refuses as `untrusted-author`.
