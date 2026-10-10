---
bump: patch
---

### Fixed

- **object-writing no longer sends a fan-out to a workflow just for the effort lever.** The skill said a bare agent spawn takes no effort parameter, which stopped being true in Claude Code 2.1.292. It now says a bare spawn takes `effort` as a workflow call does, and that a spawn passing none keeps the `object-writer` pin, with a pointer to the subagents docs section on effort.
