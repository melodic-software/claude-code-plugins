---
bump: patch
---

### Changed

- `babysit_verify_evidence.py evidence --shared-listing` judges on the run's saved artifact listing at any age and allows on it without listing again, so a run that passes it lists once for all its pull requests. Without the flag, the gate's two-minute bound and its own listing before an allow are unchanged.
