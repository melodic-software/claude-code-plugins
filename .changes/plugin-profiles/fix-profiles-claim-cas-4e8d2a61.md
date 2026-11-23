---
bump: patch
---

### Fixed

- Two applies to one folder at the same time no longer lose a record: an apply saves its record only while the record file still holds what it read, so an apply that another apply finished first re-plans over that apply's record instead of overwriting it, and `clear` can still put the file back.
