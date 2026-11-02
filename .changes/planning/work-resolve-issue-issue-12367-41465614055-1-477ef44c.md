---
bump: patch
---

### Changed

- `/planning:interview`: on an exit-0 wake the session now Reads `<data_dir>/.watch-wake.json`, where `watch.sh` writes its JSON line by itself. This replaces the old steps of reading the background task's output file, taking the last line that starts with `{` and falling back to `grep` on a partial view. The page and shared lanes' wake steps and the surface README describe the one read.
