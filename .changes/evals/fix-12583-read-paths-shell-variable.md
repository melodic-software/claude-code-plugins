---
bump: patch
---

### Fixed

- `run-validity.py` sets aside a denied read of the session's own tool results when the pipeline names the path through one leading same-command variable (`F=<path>; grep x $F`), so that read no longer fails the run (#12583).
