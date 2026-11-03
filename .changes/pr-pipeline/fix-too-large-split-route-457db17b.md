---
bump: patch
---

### Changed

- A work-resolve-issue run whose patch the scan job refused for its size (`scan-refused-patch`)
  now goes to intake for a split, with one re-entry, instead of retrying: a fresh run re-spent a
  model run on work too large for one patch. Admission parks such an issue for intake's split at
  any Size, a listed human's included, until a listed human adds `agent-ready` again, since
  re-triage rates Size from the issue text alone and would admit it at Small or Medium again.
