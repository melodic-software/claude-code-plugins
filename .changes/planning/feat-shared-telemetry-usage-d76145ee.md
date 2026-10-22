---
bump: minor
---

### Added

- The shared interview page counts taps by control, plus rage taps (three quick taps on one control) and dead taps (a tap that changes nothing), by the control's class name only. The server adds them up for everyone in each 10-minute summary batch, and `share.py logs --summary` lists them.

### Fixed

- Summary batches can no longer be matched to a fault entry's pid: repeat counts move from each summary to the batch's totals, a summary keeps only the device class, and a lone summary at shutdown is counted as dropped instead of written (#8221).
- The 10-minute summary batch is still written while the tunnel sync keeps failing.
