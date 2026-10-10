---
bump: patch
---

### Fixed

- The shared docs cache detects GNU `mv` from a here-string instead of `mv --version | grep -q GNU`. Under `pipefail` an early `grep -q` exit can break the pipe and fail the check, so a GNU `mv` was taken for a non-GNU one and directory renames took the check-and-undo fallback.
