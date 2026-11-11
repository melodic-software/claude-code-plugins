---
bump: minor
---

### Changed

- `/attribution:audit` asks for an as-of date and recheck trigger only on a record that stores an upstream value; a condensed record whose decision holds no upstream value is a pointer record (decision and pointer), and a missing stamp on one is not a finding. Expiry and trigger-less stamp checks are unchanged.
