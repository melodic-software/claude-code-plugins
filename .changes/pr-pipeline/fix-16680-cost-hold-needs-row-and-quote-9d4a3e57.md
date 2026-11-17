---
bump: patch
---

### Fixed

- The cost hold (`merge-holds.mjs` `costDecision` and ci-status's cost-only review hold step) clears only on an owner `**Decision recorded.** Cost:` comment that also links its row in the owner-decisions record and quotes the owner after `verbatim:` in double quotes; a comment that lacks either keeps the hold, and the hold's message names what it lacks. This makes a cleared hold auditable, not provable.
