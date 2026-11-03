---
bump: minor
---

### Changed

- `/harness-ops:plugins sync` reuses a `fleet-state.sh` report when nothing it read has changed since that read (each path it read keeps its mtime, ctime and size, or stays absent; a run's first read is never stored), instead of running the script again before each step. `fleet-state.sh` now lists the paths it read when `FLEET_STATE_READ_LIST` names a file. Each read and each reuse is recorded in the run journal. On this host's 92-plugin fleet with a stub CLI on Linux, a first pass went from 5 reads to 2, and an `--only-install` re-entry went from 3 reads to 2 with one install and to 0 with none ([#12539](https://github.com/melodic-software/claude-code-plugins/issues/12539)).
