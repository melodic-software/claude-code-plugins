---
bump: patch
---

### Changed

- Shared `prerequisites.mjs` synced where this plugin carries it (#6633): a manifest may declare an optional `session_probe`, which opts the plugin into harness-ops' session-start probe.
- Shared `plugin-options.mjs` synced (#6633): `readOperatorOptions` can read a boolean option stored as a JSON boolean when the caller asks for it; existing callers are unchanged.
