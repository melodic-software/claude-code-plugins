---
bump: patch
---

### Fixed

- `docpage-digest` no longer tells authors to put an ellipsis or a join marker inside a key-claim fence, which the exact-substring fence gate rejects. A fence payload is an exact contiguous substring of the source, and a truncation or a join of source lines is recorded outside the fence.
