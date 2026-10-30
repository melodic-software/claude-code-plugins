---
bump: patch
---

### Added

- `babysit_verify_evidence.py` honours `BABYSIT_VERIFY_NO_INCREMENTAL_WAITS=1`. When it is set, an
  incremental read of a carried listing that misses GitHub's live artifact count goes straight to a
  whole listing, with no wait. The count check is unchanged. Any other value keeps
  `INCREMENTAL_WAITS`.
