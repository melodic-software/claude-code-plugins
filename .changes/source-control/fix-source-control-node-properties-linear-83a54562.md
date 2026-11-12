---
bump: patch
---

### Fixed

- babysit-prs: the raw-text workflow reading in the risk scorer now strips anchors and tags and finds block-scalar openers in one linear pass, so a long workflow patch line can no longer slow the scorer.
