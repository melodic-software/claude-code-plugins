---
bump: patch
---

### Changed

- scoped-implementer: a dispatcher passes no spawn `effort`, because the Agent tool's per-spawn `effort` would replace the `effort: medium` pin; the recheck trigger that fired is replaced.
