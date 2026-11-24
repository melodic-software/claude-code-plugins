---
bump: patch
---

### Fixed

- `enable-auto-merge` rewrites its own refusal comments on a lanes App pull request once it arms it, or once GitHub accepts (or already holds) the async merge of a stack's bottom layer, saying the arm or merge request at that head superseded them and leaving no marker, so a merged pull request no longer shows a stale "unarmed at head" note.
