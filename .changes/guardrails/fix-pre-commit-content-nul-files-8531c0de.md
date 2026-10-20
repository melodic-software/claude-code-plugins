---
bump: patch
---

### Fixed

- The `pre-commit-content` git hook no longer skips a staged file holding a NUL byte. It scans that file's whole raw content for the secret patterns and blocks on a match, so one NUL byte can no longer hide a token. An ordinary binary with no match still commits, and such a file is not judged for machine-specific paths.
