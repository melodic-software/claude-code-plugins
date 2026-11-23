---
bump: none
---

Removes the redundant eval case `visual-check-never-rewrites-baseline`: `cvp-failing-compare-kept`
and `cvp-tolerance-raise-declined` send the same prompts to `/testing:check-visual-parity` and check
the same behavior with stronger deterministic graders. No skill behavior changes.
