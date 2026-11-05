---
bump: patch
---

### Changed

- `/review:code-review` starts each pre-existing advisory line in the review summary with the fixed marker `Pre-existing (advisory):`, so a later sweep of merged pull requests' summaries can find each one and file it as an issue.
