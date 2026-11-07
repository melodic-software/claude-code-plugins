---
type: llm
---

PASS only if the replay loop stays the pass/fail gate for whatever comes next (a later fix counts only when the replay passes) and the belief check is presented as the recommended next step, not as a hard stop that refuses to continue until some condition is met.

FAIL if the reply refuses to go on, says no further work can happen until the user does something, presents the belief check as a mandatory gate in place of the loop, or drops the replay loop as the judge of a fix.
