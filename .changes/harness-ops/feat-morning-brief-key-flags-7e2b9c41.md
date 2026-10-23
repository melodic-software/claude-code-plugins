---
bump: minor
---

### Added

- `/harness-ops:morning-brief` prints a `KEY:` line in the Lanes section for each credential role whose API key needs the owner, read from the runs' lane-outcome records: `auth` when a run fell back off a refused key or a key leg failed with class auth, naming the key secret to replace, and `credit-stop` when a run fell back on a credit stop, naming the role to rotate a spare key into. A role with no key problem prints nothing.

### Changed

- The Lanes section reads the newest 3 runs of every lane first, whatever their conclusion, then failed runs, all inside `--lane-read-limit`, so a key that handed off on a successful run is no longer crowded out by failed runs.
