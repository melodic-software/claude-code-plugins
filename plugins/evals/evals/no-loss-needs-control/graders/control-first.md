---
type: llm
arm: both
---

PASS if the answer says both:

1. Before the no-loss result counts, the user needs a control showing the suite can detect a loss: a version with the removed rules taken out of the old text (or otherwise degraded), run on the same cases, that scores clearly lower than the old version.
2. The trimmed version should not ship on this compare alone; if the control does not score lower, the suite cannot vouch for the cut.

FAIL if either is missing; if the answer says the trimmed version can ship now (a suggestion to also run a control afterwards does not rescue a "ship it"); or if it later contradicts or retracts this.
