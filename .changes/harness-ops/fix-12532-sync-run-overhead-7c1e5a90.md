---
bump: minor
---

### Added

- `/harness-ops:plugins sync` records each `claude` call's wall time in the run journal (`# elapsed <seconds>s, exit <rc>`), and each digest block carries `cli: {calls, seconds}`, so a run's CLI time and the script's own time can be told apart.

### Fixed

- `sync-run.sh` no longer starts one or more `jq` processes per plugin when it reads update results, builds the moved and downgraded rows, and counts monitors. On a 92-update bench with a stub CLI the first pass went from 113 s to 42 s, and an `--only-install` re-entry from 28 s to 4.4 s; the report is unchanged ([#12532](https://github.com/melodic-software/claude-code-plugins/issues/12532)).
