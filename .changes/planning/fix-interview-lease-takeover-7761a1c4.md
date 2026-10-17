---
bump: minor
---

### Added

- `round.sh lease --takeover` hands an interview over after `/clear`: one command releases the old session's lease and arms `watch.sh` for the new one. `surface.md` documents it for the after-`/clear` case.

### Changed

- A watcher whose lease was released while it waited exits 3 with a message starting `handed over, not a failure`, so a displaced watcher reads as a handover.
