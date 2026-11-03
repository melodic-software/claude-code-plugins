---
bump: patch
---

### Fixed

- the stress-test eval graders no longer pass a draft-word exclusion, a negation that bridges verbs or misses none/nothing, or an exclusion phrase that opens a real attack; a quoted claim lifts a dismissal only when a contrast word (but, however, yet) follows it, and a dismissal is also lifted when a contrast word is followed by the defect's target term. Known limits: a claim rebutted without a contrast word is not credited, and an unrelated contrast clause can still lift it

  All 48 graders in the `st-*` cases carry the tightened patterns, and 131 new
  sample answers pin them, 80 of which the old patterns sorted wrong.
