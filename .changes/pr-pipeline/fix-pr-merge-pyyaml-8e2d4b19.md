---
bump: patch
---

### Changed

- `pr-merge.yml`'s `merge` and `enable-auto-merge` jobs set up the repository's pinned Python and install only the hash-pinned PyYAML entry of `.github/requirements-ci.txt`, which the review-evidence binding needs to clear a read-only workflow-file change. A failed install warns and the job goes on, since the binding then holds every workflow change for a person. The hold-path floor documentation also states that a lane comment edited by anyone but its author unbinds the review as `comment-edited`.
