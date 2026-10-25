---
bump: patch
---

### Fixed

- Harden the session bridge: the watcher exits after 40 consecutive empty waits (exit 4) so an orphaned watcher no longer keeps the server alive, the view bridge gates the wait and lease-release endpoints with a watcher-only token that the page never receives, and U+2028 and U+2029 are escaped in output lines. The README now states the single-user-workstation limit.
