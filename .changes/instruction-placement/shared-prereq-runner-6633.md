---
bump: minor
---

### Changed

- Its `SessionStart` rows are gone (#6633): `prerequisites.json` declares `session_probe`, and harness-ops' one `SessionStart` runner starts this plugin's probe, so a missing tool or a drifted git-hook entry is still reported at session start while harness-ops is enabled. A missing `node` is reported by harness-ops' row. `hooks/hooks.json` is removed, since no hook remained.
- Shared `prerequisites.mjs` synced where this plugin carries it (#6633): a manifest may declare an optional `session_probe`, which opts the plugin into harness-ops' session-start probe.
