---
bump: minor
---

### Added

- A shared interview's named tunnel can run from any machine. Before a machine starts it, `ensure-running` asks `https://<tunnel_hostname>` itself; only Cloudflare's no-connector page (HTTP 530, Error 1033) counts as free, and any other answer or a failure to ask runs a quick tunnel and says why on stderr and in the output's `tunnelFallback`, so a second machine does not start a replica that would split the link's guests ([#8607](https://github.com/melodic-software/claude-code-plugins/issues/8607)).
- New `tunnel_api_token_file` option: the path of a Cloudflare API token with "Cloudflare One Connector: cloudflared Write", which cannot touch DNS but can change every tunnel in the account. When it is set, a session refuses the tunnel while another machine's connector is connected, points the tunnel's own hostname rule at its guest port while keeping the rest of the tunnel's configuration, and after starting checks again for a second connector or a rewritten route, so a named session can use any free port instead of 8765. The server's restart of an exited named tunnel goes through the same checks. Both token file options accept a path starting with `~/`.

### Changed

- A named tunnel whose token file is missing, empty or readable by others now falls back to a quick tunnel and says why, instead of refusing to start, so the options can be set on every machine before each one holds its files. A hostname that is not a DNS name still refuses, and a session whose named tunnel already runs keeps it and warns.
- The shared README's setup names the account API token permission "Cloudflare One Connector: cloudflared", which replaces "Cloudflare Tunnel" there.
