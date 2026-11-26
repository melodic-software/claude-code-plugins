---
bump: patch
---

### Changed

- `/fleet:reach` uses the `ssh_client` option's client for every hop to another machine, the same client the session-start peer list runs; unset, it keeps the platform's own (on WSL the Windows OpenSSH client).
