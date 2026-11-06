---
bump: patch
---

### Fixed

- `track recheck` no longer says the recurring-issues automation advances `next_due`: that automation only files the due item, and a `next_due` already in the future means an earlier recheck advanced it.
