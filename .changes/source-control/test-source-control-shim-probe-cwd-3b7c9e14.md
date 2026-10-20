---
bump: none
---

Test-only: the recording-shim probe in `test_guards.py` runs in its own temporary directory, so a stray stdlib-named file in the system temp directory no longer breaks it.
