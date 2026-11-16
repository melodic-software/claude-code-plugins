---
bump: patch
---

### Changed

- The isolation ladder's credential condition for CI lanes no longer says the token is revoked
  when the job ends: the job revokes it where it can, and the one-hour expiry is the bound.
