---
type: llm
arm: both
---

PASS if the answer says both:

1. An omitted `delta` is never 0 and is not averaged into the suite as 0.
2. It means the arms were not comparable, so the case is reported as not comparable.

FAIL if the answer counts the missing delta as 0, averages it in as 0, fills it in from the arm scores, or later contradicts or retracts this.
