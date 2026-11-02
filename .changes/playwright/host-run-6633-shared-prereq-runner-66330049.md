---
bump: patch
---

### Changed

- The `SessionStart` node-notice row is gone (#6633): harness-ops' row reports a missing `node` for the whole fleet, once per session. Without harness-ops, no session-start notice says `node` is missing.
- Shared `prerequisites.mjs` synced where this plugin carries it (#6633): a manifest may declare an optional `session_probe`, which opts the plugin into harness-ops' session-start probe.
