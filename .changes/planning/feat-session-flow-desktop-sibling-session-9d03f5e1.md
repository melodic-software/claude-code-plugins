---
bump: patch
---

### Changed

- **`plan` and `interview` no longer assume `/clear` starts the next session.** After an approved plan, `plan` recommends a fresh session and defers how it starts to `/session-flow:workflow` when that plugin is enabled, which on the desktop app can be a new session started from the handoff; `interview`'s wayfind handoff says the same of the session that reads the ledger.
