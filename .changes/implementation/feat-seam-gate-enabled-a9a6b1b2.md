---
bump: patch
---

### Changed

- Optional calls to another plugin's skills are gated on that plugin being enabled, so a plugin that is installed but switched off takes the documented fallback, per the seam-phrasing contract.

### Fixed

- `/implementation:implement-dispatch`'s test-first brief line cites `/implementation:implement` Step 2, where the test-first cadence lives, instead of Step 3.
