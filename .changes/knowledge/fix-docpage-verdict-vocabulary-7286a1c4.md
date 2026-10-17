---
bump: patch
---

### Changed

- `docpage-digest` dual verification now defines the verdict set (PASS / PASS-WITH-FINDINGS / FAIL / BLOCKED), the rule that sets it (any open high finding is FAIL and needs a corrections round), and that medium or low findings deferred to the interview handoff do not block Phase 4 completion.
