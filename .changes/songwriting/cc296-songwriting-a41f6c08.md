---
bump: patch
---

### Fixed

- **object-writing no longer sends a fan-out to a workflow just for the effort lever.** The skill said a bare agent spawn takes no effort parameter, which stopped being true in Claude Code 2.1.292. It now sets effort on each spawn whichever surface dispatches it, with a pointer to the subagents docs section on effort.
