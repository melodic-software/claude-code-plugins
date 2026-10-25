---
bump: patch
---

### Fixed

- The `/planning:interview` page header no longer reads `Idle` for up to 30 seconds while an event waits and no watcher is waiting or holding the lease. It now names the waiting question or event at once, as in `Not listening for Q3: type next` (or `Not listening for Q3: approve any prompt in the terminal, or type next` while no watcher has ever polled). A delivery left unhandled for ten minutes is named the same way. The question chips and the receipt line keep their 30-second grace ([#8170](https://github.com/melodic-software/claude-code-plugins/issues/8170)).
