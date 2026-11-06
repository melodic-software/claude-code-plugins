---
bump: patch
---

### Changed

- `/harness-ops:changelog apply`'s native-drift filing reads work-items' `filing_posture` on an
  unattended run: `manual-only`, the default, files nothing and lists the items as unfiled; only
  `allowed` files without asking. Interactive runs keep the one batch confirmation.
