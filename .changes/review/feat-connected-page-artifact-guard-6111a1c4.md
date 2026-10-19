---
bump: minor
---

### Added

- A PreToolUse guard on the Artifact tool denies publishing an HTML page whose content security policy names a loopback `connect-src` (a connected page, which works only on this machine). Switch it off with the `connected_page_guard_enabled` option.
- `/review:check` reports whether node resolves and the guard is registered.
