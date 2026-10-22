---
bump: patch
---

### Fixed

- The view bridge's local server starts at once on macOS: it no longer resolves 127.0.0.1 to a host name (socket.getfqdn) when it binds, a lookup that took about 35 seconds on a macOS runner.
