---
bump: patch
---

### Fixed

- Check 21 (fresh-eyes declarations) now also matches the completion gate a self-check closes, "called done" or "calling it done", so a step where the maker reads its own output back before the work is called done WARNs unless a fresh-context judge is declared nearby. It matches the gate phrase, not "read back", which far more often names a mechanical read of written data.
