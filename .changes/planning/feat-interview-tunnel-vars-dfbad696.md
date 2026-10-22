---
bump: minor
---

### Changed

- `/planning:interview` now passes the `tunnel_hostname` and `tunnel_token_file` options to a shared session, so a configured named tunnel starts without restating it; an unset hostname runs a quick tunnel.
