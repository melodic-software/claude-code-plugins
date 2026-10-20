---
bump: patch
---

### Fixed

- A restatement after a compaction now absorbs an approach or threshold line recorded before it, so Claude no longer gets `smart zone (1 of 3), nearing acceptable` beside `dumb zone (3 of 3, compacted)`. A threshold keeps its action sentence, which the restatement does not carry.
- Operator mode: a crossing held at the end of a turn is merged into a restatement the same way before the suggestion is built, so the person is not offered both.
- A crossing toast no longer waits on the snapshot write at `session.measure`: the toast shows first, and the write still runs if the toast step fails.
