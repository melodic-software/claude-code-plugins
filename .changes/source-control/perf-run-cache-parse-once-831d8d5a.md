---
bump: patch
---

### Changed

- The pr-merge run cache is parsed once per gate process until another process replaces it, and its shared run records keep only each repository's `full_name`, the one field their readers check. A verifier read no longer re-parses a multi-megabyte file on every lookup.
