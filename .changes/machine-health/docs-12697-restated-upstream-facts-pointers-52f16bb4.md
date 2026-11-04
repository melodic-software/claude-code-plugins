---
bump: patch
---

### Changed

- `setup` no longer states which settings file either `plugin configure` route writes. It keeps
  the scope and failure-signal guidance with their reasons, and points at the `plugin configure`
  and `plugin install` sections of the plugin commands reference.
- The Windows check catalog's environment and PATH health entry no longer names the System
  Properties editor as the source of the 2047 User Path `CRIT` threshold; it keeps that further
  appends are silently discarded.
