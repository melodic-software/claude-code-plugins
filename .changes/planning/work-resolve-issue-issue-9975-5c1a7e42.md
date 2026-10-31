---
bump: minor
---

### Added

- The shared interview server now sends Claude a `fault-spike` event when 3 faults of one kind arrive within 300 seconds. The kinds are page `error`, `rejection` and `api` entries, plus the server's own 5xx answers. After one event, none follows for 600 seconds. The event carries only the server's counts: the fault kind, the count, the window and the threshold. It never carries a fault's message, source, route, fingerprint or pid. Claude handles it like a problem report: it diagnoses the spike and proposes a fix to the owner in the terminal ([#9975](https://github.com/melodic-software/claude-code-plugins/issues/9975)).
