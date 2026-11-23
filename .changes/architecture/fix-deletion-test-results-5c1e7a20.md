---
bump: patch
---

### Fixed

- The deepening scan's two deletion-test results now mean one thing everywhere: the vocabulary defines `concentrates` (a module that only forwarded calls, or shallow modules that fold into one, a candidate) and `moves` (logic every caller would copy, a module that earns its keep), and the scan briefing no longer calls `moves` a pass-through.
- A pass-through candidate's `solution` line may name which of the three fixes applies: delete it, move work between it and what it wraps, or merge the two.
- Design-It-Twice launches each design as a fresh subagent, never a fork.
- `/architecture:improve` names `/testing:write` next when an agreed candidate's module has no tests to protect the refactor.
