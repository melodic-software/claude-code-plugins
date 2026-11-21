---
bump: patch
---

### Fixed

- **babysit-prs:** the post-merge floor read with no local clone of main now pages through the commits API instead of failing once the enabled `pr-pipeline.yaml` run passes 100 commits. It still fails closed when a page cannot be read or the run passes 5000 commits.
