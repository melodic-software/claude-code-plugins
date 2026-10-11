---
bump: patch
---

### Fixed

- `/harness-ops:behavior-probes`: on Windows the runner starts case scaffolds with Git for Windows bash by full path and a POSIX script path, instead of a bare `bash` that can resolve to WSL and exit 127 before any model call; it reports an error when Git's bash is missing. `records.md` gains a Windows rerun at Claude Code 2.1.296.
