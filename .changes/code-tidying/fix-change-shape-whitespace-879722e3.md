---
bump: patch
---

### Fixed

- `change-shape.py` now reads CODE-CHANGED (exit 20), not COMMENT-ONLY or DOCSTRING-ONLY, when an edit changes whitespace on a code line (`x = (` to `x =(`, a reindent, a line split or joined); deleting whole comments, trailing ones included, still passes.
