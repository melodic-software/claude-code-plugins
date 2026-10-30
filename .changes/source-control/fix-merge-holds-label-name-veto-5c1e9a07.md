---
bump: patch
---

### Fixed

- `babysit_merge.py` no longer reads a person naming the `do-not-merge` label (in backticks, before "label", or as a list item after a comma) as a "do not merge" veto. A sentence that says not to merge, or a bare `do-not-merge`, still holds the merge.
