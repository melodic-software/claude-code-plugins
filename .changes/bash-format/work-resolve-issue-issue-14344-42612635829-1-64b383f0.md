---
bump: patch
---

### Changed

- Simplified the vendored git-hook check library and installer. They behave the same, but a git-hook copy you already installed shows as stale until setup refreshes it, because the copy's stamp covers the library's text.
