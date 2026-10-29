---
bump: patch
---

### Fixed

- `/harness-ops:plugins` sync: the report's `Normalized:` row now says how many `enabledPlugins` keys moved, `1 of 101 keys moved` for one appended key, instead of counting every key as reordered. `normalize-enabled-plugins.sh` prints `normalized moved=K keys=N` (and `would-normalize moved=K keys=N` under `--check`), K being the fewest keys the reorder moves.
- `normalize-enabled-plugins.sh` prints `missing-file keys=0` (exit 0) when the settings file does not exist, rather than `already-sorted keys=0`, and the report renders it as `Normalized: skipped, no user settings file`.
