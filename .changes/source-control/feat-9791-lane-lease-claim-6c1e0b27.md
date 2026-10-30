---
bump: patch
---

### Fixed

- A push that touches `plugins/work-items/tools/work-item-tracker/**` stops an approval carrying, since the read runner's issue-mode lease and `work-resolve-issue.yml` now run the tracker.
