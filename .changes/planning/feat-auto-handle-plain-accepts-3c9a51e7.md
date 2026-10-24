---
bump: patch
---

### Changed

- The interview server marks a plain accept (no text) and a plain confirm handled when it saves them, so the watcher wakes only for events that need a reply. The responses document, `sync-ledger` and `export-brief` record them as before. The accept that settles the last open question of a round stays unhandled, so the agent learns the round is complete. Undo of an auto-handled accept still works until the agent handles a later event; the "Claude already handled it" refusal applies to agent-handled events. The interview surface reference lists which events are auto-handled.
