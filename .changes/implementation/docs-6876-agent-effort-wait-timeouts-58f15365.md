---
bump: patch
---

### Changed

- The `implementer`, `scoped-implementer` and `phase-verifier` model-binding sections now state the rule for the Agent tool's per-call `effort`: a dispatcher omits it and never passes one below the agent's pinned effort.
- `implement-dispatch` briefs a worker waiting on CI to pass each wait an explicit timeout sized to the CI run and to restart the wait at the deadline notice, pointing at the tools reference for the limits.
