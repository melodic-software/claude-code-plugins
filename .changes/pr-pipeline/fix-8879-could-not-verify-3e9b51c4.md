---
bump: patch
---

### Fixed

- `check-signed-commits` reports a pull request it could not check (its head never matched its branch, or its commits could not all be listed) as "could not verify the lane's commits" in its log and escalation comment, instead of "unverified commits" with no commit named. It still fails closed.
