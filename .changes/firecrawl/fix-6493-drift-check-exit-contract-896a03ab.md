---
bump: patch
---

### Fixed

- `/firecrawl:update --check` no longer counts a firecrawl CLI that is not installed as drift: it reports it and exits 0 when upstream is unchanged, so its exit codes follow the shared drift-check contract (0 no drift, 1 drift, 2 unverifiable). (#6493)
- The `--check` report prints the recorded last-sync date and SHA256 instead of `recorded)`: a never-synced placeholder such as `(none recorded)` now reads as empty. (#6493)
