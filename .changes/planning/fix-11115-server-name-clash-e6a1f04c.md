---
bump: patch
---

### Fixed

- The interview surface's `server.py` and `test_server.py` are now `interview_server.py` and
  `test_interview_server.py`, so `pytest plugins/planning` no longer stops on an import file
  mismatch, and a surface module can no longer import the shared `server.py` in its place.
