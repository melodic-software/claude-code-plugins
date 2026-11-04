---
bump: patch
---

### Fixed

- `read` passes a URL found in fetched text through the gate exactly as written: the whole token up to the next whitespace. A token the gate refuses stays refused, never trimmed into one that passes.
