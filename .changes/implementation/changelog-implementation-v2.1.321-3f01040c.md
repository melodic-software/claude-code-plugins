---
bump: patch
---

### Changed

- `implement-dispatch` no longer counts the `best` alias as the frontier tier on Claude Code v2.1.321 and later, where `best` resolves to the same model as `opus`; the concurrent-wave rule still treats `best` as frontier on older versions, and now links the model-config version history.
