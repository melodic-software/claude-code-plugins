---
bump: patch
---

### Changed

- **`kill-all` is a recovery step, not how a run starts.** The quick start no longer opens with `kill-all`, and the "`kill-all` at the start" convention is replaced by a "Recover from stale sessions" subsection: `kill-all` stops every daemon on the machine, so it is for stale daemons or socket errors when no other run may be live, and a run closes only its own named sessions. The orchestrator recipe drops its `kill-all` first step and its between-batches `close-all && kill-all` advice to match.
