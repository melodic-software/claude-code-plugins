---
bump: patch
---

### Changed

- The rendered-view reference treats `medium: hosted` as `artifact`: the blindspot view is never sent to a page host.
- Shared `view-runtime.js` synced: a page served top-level over `https:` keeps its save button.
