---
bump: patch
---

### Fixed

- `enable-auto-merge` rewrites its own refusal comments on a lanes App pull request once it arms it, saying the arm at that head superseded them and leaving no marker, so a merged pull request no longer shows a stale "unarmed at head" note.
