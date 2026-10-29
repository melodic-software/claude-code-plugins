---
bump: minor
---

### Added

- A shared interview's named tunnel can run from any machine. Before a machine starts it, `ensure-running` asks `https://<tunnel_hostname>` itself; when another interview session or another machine's cloudflared answers, the session runs a quick tunnel and says why on stderr and in the output's `tunnelFallback`, so two machines never split the link's guests ([#8607](https://github.com/melodic-software/claude-code-plugins/issues/8607)).
- New `tunnel_api_token_file` option: the path of a tunnel-only Cloudflare API token ("Cloudflare One Connector: cloudflared Write"). When it is set, each session points the tunnel's route at its own guest port, so a named session can use any free port instead of 8765.

### Changed

- A named tunnel whose token file is missing, empty or readable by others now falls back to a quick tunnel and says why, instead of refusing to start, so the options can be set on every machine before each one holds its files. A hostname that is not a DNS name still refuses.
- The shared README's setup names the account API token permission "Cloudflare One Connector: cloudflared", which replaces "Cloudflare Tunnel" there.
