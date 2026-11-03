---
bump: patch
---

### Fixed

- the stress-test eval graders no longer pass a draft-word exclusion, a negation that bridges verbs or misses none/nothing, or an exclusion phrase that opens a real attack; a dismissal is lifted only when a contrast word (but, however, yet, although, though) is followed by the defect's target term, so a quoted claim rebutted another way is not credited (known limit)

  All 48 graders in the `st-*` cases carry the tightened patterns, and 130 new
  sample answers pin them, 76 of which the old patterns sorted wrong.
