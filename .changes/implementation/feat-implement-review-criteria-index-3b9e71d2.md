---
bump: minor
---

### Changed

- `/implementation:implement` reads the repository's review-criteria index before the first edit,
  as the standards contract's "Review-criteria index" paragraph directs, loading only the rows the
  paths it will edit touch.
