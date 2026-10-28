---
bump: patch
---

### Fixed

- The `wip.pause-from` docs state that leaving it empty removes intake admission's queued cap: over that cap check-wip-cap leaves admissions open with no room limit, so intake still adds `agent-ready`. An incomplete or failed queued read still defers. An intake admission test covers the empty case.
