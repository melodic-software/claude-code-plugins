---
bump: patch
---

### Fixed

- `implement-dispatch` briefs, `implementer` and `scoped-implementer` tell a worker to name scratch files `<branch>-<purpose>` and never run a scratch script it did not write in this task, so parallel workers sharing one scratchpad stop running each other's leftover scripts.
