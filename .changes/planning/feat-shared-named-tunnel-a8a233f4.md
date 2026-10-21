---
bump: minor
---

### Added

- Shared interview sessions can run on a named Cloudflare tunnel: set the new `tunnel_hostname` and `tunnel_token_file` options on one machine, and the guest link stays `https://<hostname>` across restarts and reboots. cloudflared reads the token through `--token-file`; it is never on a command line or in output.
- `shared/cfdns.py`, the owner's Cloudflare checks: a read-only zone listing that shows the one proxied CNAME the tunnel needs and any clash, a write of exactly that record only behind `--confirm <hostname>`, and a check that only one machine runs the tunnel.

### Changed

- Switching a running session to another tunnel address keeps the old tunnel up for ten minutes; a page open there moves to the new address and keeps the guest's name and answers.
