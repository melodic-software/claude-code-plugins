---
bump: patch
---

### Added

- `behavior-probes`: three `hub-start` case pairs, each case beside its control: an `rm -rf` of a 200-file tracked directory in the sibling repository named only by a file in the hub (expected denied) against the same command named by the prompt; whether the sibling's `CLAUDE.md` loads on a Read by absolute path, against a hub subdirectory's `CLAUDE.md`, read from an `InstructionsLoaded` hook log; and where a subagent spawned with `isolation: "worktree"` runs, against one spawned with no isolation. New scaffolds `cases/lib/hub-fixtures.sh`, `instructions-probe.sh` and `cwd-probe-agent.sh` build them inside the run's temp directory. The cases are listed as pending in `records.md` until their first live run.
