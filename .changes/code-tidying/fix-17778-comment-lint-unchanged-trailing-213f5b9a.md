---
bump: patch
---

### Fixed

- The comment lint no longer judges a changed line whose trailing comment text is byte-identical to that of the base line it replaces, so a formatter that respaces or rewraps the code before an existing comment passes. A comment whose text changed, a new trailing comment and a full-line comment still fail. Lines pair in order within a hunk that adds as many lines as it removes; in any other hunk, a line pairs only with the one removed code line carrying the same comment, and otherwise it is judged.
