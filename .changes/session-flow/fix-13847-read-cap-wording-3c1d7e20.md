---
bump: patch
---

### Fixed

- `save_point.py validate`'s Read-page-cap FAIL now says the resume prompt's default Read returns only the first page with a PARTIAL view notice, instead of saying one Read cannot hold the file; a Read with `allow_large` can (#13847).
