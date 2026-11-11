---
bump: minor
---

### Changed

- The workflow router reads context-guard's compaction marker beside the zone instead of as a
  degraded zone: between human stages it suggests a handoff at zone `heavy` or on the marker.
- The router clears rather than compacts between attended work items whose ticket, spec, plan or
  decomposed item on disk already holds everything the next item needs.
- After failed attempts made through file-edit tools in an attended session, the router offers
  `/rewind` with a restore option first, with its limits; never for orchestrated work.
- The handoff route suggests `/rename` when the user may want the session back through `/resume`.
