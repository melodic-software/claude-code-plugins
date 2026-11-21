---
bump: patch
---

### Changed

- Unattended `/improvement:find` reads an architecture candidate's Size from the entry's `size` field instead of judging it from the files and text; an entry without one is reported as a gap.
