---
bump: patch
---

### Changed

- `repository_is_archived` keeps each repository's archived flag for the life of the process, keyed by the casefolded repository, so a PR queue snapshot of N pull requests in one repository makes one archived read instead of N, and `request_review.py`'s re-read after the request reuses the first answer. A failed read is not kept.
