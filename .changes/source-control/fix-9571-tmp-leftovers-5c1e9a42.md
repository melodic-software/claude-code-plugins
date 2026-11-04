---
bump: patch
---

### Fixed

- The pull-request monitor's poll script removes its stderr temp file on every exit, a stopped watch included. Each watch and snapshot run left one empty file in the temp directory (#9571).
- `fetch-failed-logs.sh` removes the temp scratch directory it creates when no plugin data directory holds the scratch. It keeps it only for `--keep-zip` and for an exit 3 or 4 whose message names the file. Each run left a directory behind, empty after a failed fetch (#9571).
