---
bump: patch
---

### Changed

- `babysit_verify_evidence.py` drops `BABYSIT_VERIFY_NO_INCREMENTAL_WAITS`. Every caller now takes
  the incremental read's waits, which stop at the caller's limit (`BABYSIT_VERIFY_DEADLINE_SECONDS`).
