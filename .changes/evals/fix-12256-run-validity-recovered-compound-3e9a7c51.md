---
bump: patch
---

### Fixed

- `run-validity.py` sets aside a with-arm denied compound Bash call as a warning when a later call in the same run ran its plugin part alone and was allowed, so a state-saving skill whose model wraps a prescribed script call in `cd`, assignments or a trailing `ls` can still score VALID; a denial whose plugin part never ran alone still fails (#12256).
