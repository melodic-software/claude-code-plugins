---
bump: patch
---

### Changed

- The issue lane skips an umbrella, an `agent-ready` issue with an open sub-issue, before any model run. It keeps `agent-ready`, logs a notice naming the open sub-issues, and work-unblock's sweep re-fires it once none is open. The WIP cap no longer counts such an issue as queued work. Neither path adds `needs-human`.
- A run may stop with the `umbrella` code. `stop-routes.json` routes it `fail`: `agent-ready` removed, no label added, and an `outcome=failed` marker.
