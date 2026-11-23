---
bump: patch
---

### Changed

- measure-delivery: `merge-risk-failures.mjs` reads a record's first line through an exported `parseRecordMarker`, which runs the shared post-merge record vectors. No behavior changes.
