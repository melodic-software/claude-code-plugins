---
bump: none
---

### Fixed

- **`block-root-delete-target` test suite passes on Windows Git Bash (#6627).** The relative-root fixture now drops a drive prefix as well as a leading slash, so it is relative on every host, and the `/` top-level-path case is skipped with a printed reason where `/` is the Git install directory rather than a volume root. The guard is unchanged.
