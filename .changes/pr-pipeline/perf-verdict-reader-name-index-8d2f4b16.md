---
bump: minor
---

### Changed

- A pr-verify FAIL first uploads one index artifact per tie the merge gate counts (`.github/actions/upload-fail-index`), and uploads only once every index did; a job without the index step writes no FAIL. The gate reads those exact names instead of the whole artifact listing once the legacy FAILs file is committed.
