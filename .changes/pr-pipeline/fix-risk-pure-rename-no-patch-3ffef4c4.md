---
bump: patch
---

### Changed

- The risk score's `unreviewed-patch` rule states that a rename or copy whose base blob and mode at the old path equal the head's at the new path does not hold, and that an unknown blob still does.
