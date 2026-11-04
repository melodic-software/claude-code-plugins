---
bump: patch
---

### Fixed

- `sweep-all` preflight: stage 1 no longer reads `run_in_background` as a fork-mode signal, since the
  docs relate fork mode only to what a dispatched call that omits it does; it reads whether the
  `Agent` tool offers the `fork` type and still never gates. Stage 1b and the closing note drop the stale default and rollout wording and
  point at the docs section. Stage 2 stays the decider.
