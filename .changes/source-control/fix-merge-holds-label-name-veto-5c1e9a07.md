---
bump: patch
---

### Fixed

- `babysit_merge.py` no longer reads a person writing "the `do-not-merge` label" as a "do not merge" veto. Any other `do-not-merge`, a comma list included, and a sentence that says not to merge still hold the merge.
