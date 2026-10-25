---
bump: minor
---

### Added

- **`block-cross-domain`, a guard on the Bash and PowerShell row that classifies each call against a machine-local identity-domain map (#9743).** It reads `${CLAUDE_PLUGIN_DATA}/identity-domains.json`: `domains.<name>` with per-OS `roots`, `owners`, `identity_markers` and optional `gh_config_dir` and `az_config_dir`, then top-level `identity_files`, `shared_exceptions` and `messages`. It compiles the map with `jq` once per change into `identity-domains.cache` and reads that back with builtins, classifies the session cwd into the domain whose root holds it or neutral, and parses a command only when its text names a configured root or marker. It never denies a call: the result goes to the telemetry envelope (`cwd` and `form`, never a domain name), and a malformed map tells the user once per session. With no map it reads and parses nothing. The `block_cross_domain_enabled` option turns it off.
