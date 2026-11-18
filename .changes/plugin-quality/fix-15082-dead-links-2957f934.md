---
bump: patch
---

### Fixed

- The config audit's silent no-op key check points at the 2.1.323 changelog entry and an
  archived capture of the manifest reference, in place of the removed "Default settings" section,
  and flags every key but `agent`, since 2.1.323 removed `subagentStatusLine` and deprecated
  `agent`.
