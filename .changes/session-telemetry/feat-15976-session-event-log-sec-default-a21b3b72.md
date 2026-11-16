---
bump: patch
---

### Fixed

- With `session_event_log_categories` set, the session event log's hooks module registers only the events in those categories, plus `SessionEnd` for retention, so an event outside them starts no process. Where the built-in guard `sec-default` holds `classic.*` events, it now holds only the events you chose. `SessionEnd` writes its record only when `session` is listed. The README says where the guard loads and which administrator actions let the log run there.
