---
bump: patch
---

### Fixed

- `babysit_verify_evidence.py settle --idle-tick --fresh` settles a post-merge report its caller's own check just made without the idle tick's verifying-runs test, so a run that completed while the check ran no longer refuses it; the report checks, the lane room's rule and the quarantine and pin reads still apply.
