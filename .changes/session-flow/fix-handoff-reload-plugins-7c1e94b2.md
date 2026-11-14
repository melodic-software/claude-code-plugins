---
bump: patch
---

### Fixed

- `/session-flow:handoff` tells the user to type `/reload-plugins` after `/clear` and before
  pasting the resume prompt when a plugin was installed, updated, enabled or disabled during the
  session, and records that step under Environment to re-establish. It no longer lets a handoff
  say that `/clear` or the resume prompt loads the updated plugin.
