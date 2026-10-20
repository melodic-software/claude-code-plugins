---
bump: patch
---

### Fixed

- The shared git-hook check library reads the range diff with `--text`, so a tracked `-diff` attribute no longer hides a text file's added lines from a check, and drops a file whose content holds a NUL byte in its first 8000 bytes, so binary content never reaches a check as changed lines.
