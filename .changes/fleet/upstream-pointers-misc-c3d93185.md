---
bump: patch
---

### Changed

- `/fleet:reach` stops restating error strings and documented flag behavior, and dates its measured per-turn cost; it keeps our probe results and decisions and points at the live sections (errors, cross-session messaging, CLI flags, auto mode) with an as-of date and recheck trigger.
- `/fleet:reach` no longer states a per-turn cost figure in its body; it links the costs page and keeps the dated measurement in its relay reference's Cost row.
