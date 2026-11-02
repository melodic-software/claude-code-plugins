---
bump: minor
---

### Added

- One `SessionStart` row, `hooks/prerequisites-fleet.mjs`, runs the prerequisites probe of every enabled plugin whose `prerequisites.json` declares `session_probe`, with that plugin's own root and data directory, and prints their notices as one message (#6633). It skips a plugin whose kill switch the operator's settings turn off, and reads enabled plugins from the settings files, never from `claude plugin list`. The other plugins' per-plugin node-notice and probe rows are gone; harness-ops' node-notice row is now the fleet's only one.

### Changed

- Shared `prerequisites.mjs` synced where this plugin carries it (#6633): a manifest may declare an optional `session_probe`, which opts the plugin into harness-ops' session-start probe.
- Shared `plugin-options.mjs` synced (#6633): `readOperatorOptions` can read a boolean option stored as a JSON boolean when the caller asks for it; existing callers are unchanged.
