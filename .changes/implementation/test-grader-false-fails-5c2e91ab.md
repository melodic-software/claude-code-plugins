---
bump: patch
---

### Fixed

- Four eval graders that failed correct runs: `stop-on-mismatch` accepts "equals ... If it doesn't,
  STOP" and "If not, STOP"; `verifier-runs` no longer fails a line whose later "no" is about
  something other than the verifier; `phase-not-done` skips an unbolded `plan said:` field; and
  `reports-repo-layer` accepts "comes from the repo file".
