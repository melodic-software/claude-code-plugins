---
bump: patch
---

### Fixed

- `plan` now says to make the checklist copy by reading `templates/checklist.md` and writing it with
  the Write tool, never `cp`, `sed` or a shell redirect from a plugin file, which a sandbox that
  denies writes sourced from the plugin root refuses.
