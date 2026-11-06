---
bump: patch
---

### Fixed

- The pr-merge lane writes no reasons comment, cleared comment or risk escalation on a pull request whose author App is in `adoption.self-merging-apps`, an App that enqueues and merges its own pull requests; its risk score still holds the lane's own merge.
