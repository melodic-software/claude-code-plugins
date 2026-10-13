---
bump: patch
---

### Changed

- The `implementer`, `scoped-implementer` and `phase-verifier` model-binding sections now state the rule for the Agent tool's per-call `effort`: a dispatcher omits it and never passes one below the agent's pinned effort.
- `implement-dispatch` briefs a worker waiting on CI to set each wait's timeout explicitly, sized to the CI run, and to check the run's state and wait again when a wait ends before CI does, pointing at the tools reference for the time-limit rules. The trail-review dispatch passes no per-call `effort`.
