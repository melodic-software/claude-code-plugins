---
bump: patch
---

### Changed

- `babysit-prs` no longer prints its evidence checklist on an iteration where nothing materially
  changed: the checklist is still completed and written to the working-notes file every
  iteration, where the next iteration reads its `Subscribed PRs` line, and what the loop prints
  follows its Reporting section.
