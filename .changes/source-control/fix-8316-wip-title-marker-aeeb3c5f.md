---
bump: patch
---

### Fixed

- `pull-request ready` holds the flip only for a WIP marker in the title (a leading `WIP` or `WIP:`, `WIP` after the type prefix, or a `[WIP]` or `(WIP)` tag), not for a WIP mid-sentence such as "the issue-lane WIP cap".
