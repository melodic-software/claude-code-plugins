---
bump: patch
---

### Fixed

- the stress-test eval graders no longer pass a draft-word exclusion, a quoted claim the answer goes on to dispute, a negation that bridges verbs or misses none/nothing, or an exclusion phrase that opens a real attack

  All 48 graders in the `st-*` cases carry the tightened patterns, and 129 new
  sample answers pin them, 93 of which the old patterns sorted wrong.
