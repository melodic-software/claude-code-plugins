---
bump: patch
---

### Fixed

- The pr-merge lane's escalation to a person (risk, verifier, held-major and shared-copy) is posted as a new comment beside the human-gated label instead of an edit of its earlier comment, so the escalation notifies and the head-moved clear pairs the label with the newest escalation comment. An unchanged escalation is not posted again.
