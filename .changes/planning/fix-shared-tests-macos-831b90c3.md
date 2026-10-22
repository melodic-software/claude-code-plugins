---
bump: patch
---

### Fixed

- The local server answers its first request on macOS within share.py's start limit: its listeners no longer resolve 127.0.0.1 to a host name (socket.getfqdn) when they bind, a lookup that took about 35 seconds on a macOS runner.
