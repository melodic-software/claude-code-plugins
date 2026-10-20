---
bump: patch
---

### Fixed

- The changelog fragment writer adds a later entry under the existing heading instead of repeating it, and writes nothing during a merge
  (#7218).

  It no longer edits fragments that came in from other branches.
