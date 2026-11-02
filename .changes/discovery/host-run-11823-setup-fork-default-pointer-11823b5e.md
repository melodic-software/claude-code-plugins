---
bump: patch
---

### Fixed

- `setup` reads the unset fork-mode default from the docs instead of a stale copy

  The check's fork-availability row no longer states that fork mode is off by default in `claude -p` and the SDK. It reads the default for the observed version and session kind from the sub-agents page's "Turn fork mode off" section, recorded with an as-of date and recheck trigger. A new eval case, `su-fork-default-print-mode`, asks the check for that default in `-p` runs.
