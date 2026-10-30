---
bump: patch
---

### Fixed

- The control-claude-code driver no longer loses its session on Windows at the first command that takes longer than a ping, such as `screenshot`. The client kept the connection open for the reply instead of half-closing a named pipe that does not stay half-open, and the session holder ignores a client that disconnects early instead of crashing with an unhandled `EPIPE`.
