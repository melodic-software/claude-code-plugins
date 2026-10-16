---
bump: patch
---

### Changed

- `boris`: the formatting-hook tip runs the formatter once per batch from `PostToolBatch` and again at git `pre-commit`, in place of a per-edit `PostToolUse` hook. The vendored upstream baseline still matches upstream v8.16.0.
