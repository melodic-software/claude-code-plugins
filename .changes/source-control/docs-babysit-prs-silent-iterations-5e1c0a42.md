---
bump: patch
---

### Changed

- `babysit-prs` prints nothing on an iteration where no PR materially changed. Every iteration
  still completes its evidence checklist and writes it to `babysit-checklist.md` in the working-notes
  location, where the next iteration reads its `Subscribed PRs` line; an iteration with a material
  change prints the Reporting lines followed by the completed checklist.
