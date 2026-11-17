---
bump: patch
---

### Fixed

- The concurrent-sessions example in `reference/sessions.md` waits on each `open` by pid, so a failed open is reported instead of hidden by a bare `wait`.
