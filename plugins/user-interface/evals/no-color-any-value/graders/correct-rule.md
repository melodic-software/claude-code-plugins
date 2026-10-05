---
type: llm
arm: both
---
PASS only if the answer tells the developer that NO_COLOR=0 must turn color off, because the rule is
that NO_COLOR being present and non-empty disables color whatever its value. FAIL if it treats 0 as
false or enabling color, or leaves the value question unanswered.
