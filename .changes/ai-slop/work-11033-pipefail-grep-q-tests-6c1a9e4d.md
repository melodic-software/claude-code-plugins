---
bump: none
---

Test-only change: the excerpt-truncation checks in `detect.test.sh` match the detector output with a here-string instead of a pipe into `grep -q`, so under `set -o pipefail` a match can no longer read as a miss. No shipped behavior changes.
