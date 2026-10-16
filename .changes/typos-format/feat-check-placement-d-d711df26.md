---
bump: patch
---

### Fixed

- The pre-push range reader treats an all-zero object id of any width as zero, so in a SHA-256 repository a new branch is checked from its merge-base and a deletion is skipped instead of the hook checking nothing.
