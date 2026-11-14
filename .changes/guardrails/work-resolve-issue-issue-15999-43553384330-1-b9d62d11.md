---
bump: patch
---

### Fixed

- The pre-commit and pre-push checks now test the changed files for binary content with a fixed number of processes instead of three per file. Each check reads the index, or each pushed tip, through one listing and one `git cat-file --batch`, and reads work tree files with no extra process. On Windows, a commit that staged a few hundred files spent minutes starting git once per file. A file still counts as binary only when its first 8,000 bytes hold a NUL byte, whatever its attributes say. Installed hooks report drift until reinstalled.
