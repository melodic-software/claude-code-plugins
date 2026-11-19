---
bump: patch
---

### Fixed

- `tidy_work.py clean` keeps every file of a handoff chain whose newest hot file is not closed
  (`Next: none (closed)`), whatever its age or the state of the pull requests it names, and
  prints one `kept open chain:` line per such chain.
