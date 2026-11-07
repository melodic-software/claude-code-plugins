---
type: llm
focus: trace
arm: both
---
Expectation: "The response routes the review to /user-interface:audit or the
animation-audit concern".

PASS only if the run invokes `user-interface:audit` with the Skill tool, or the reply routes the
review to `/user-interface:audit` or the animation-audit concern. FAIL if the run reviews the
branch's animation itself with neither, or routes the review somewhere else.
