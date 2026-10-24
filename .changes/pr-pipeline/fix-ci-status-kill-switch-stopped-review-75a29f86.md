---
bump: patch
---

### Fixed

- ci-status fails a ready pull request whose review lane the kill switch stopped (`CLAUDE_LANES_DISABLED`, `CLAUDE_LANES_REPO_DISABLED`, or a lane's own `CLAUDE_REVIEW_DISABLED` or `CLAUDE_SECURITY_REVIEW_DISABLED`), naming the lane: "did not run on <head>: the kill switch is on. Re-trigger the PR once it is off." Before, a stopped lane passed, so a head pushed while the switch was on could merge with no review. The kill switch pauses review and never waives it; the admin bypass stays the break-glass.
