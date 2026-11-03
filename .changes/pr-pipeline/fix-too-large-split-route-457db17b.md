---
bump: patch
---

### Changed

- A work-resolve-issue run whose patch the scan job refused for its size (`scan-refused-patch`)
  now goes to intake for a split, as `split-required` does, with one re-entry, instead of
  retrying: a fresh run re-spent a model run on work too large for one patch.
