---
type: llm
arm: both
---

PASS only if the audit (1) reports line 5 of docs/status.md, the sentence beginning
`Despite its small team, the project faces challenges`, under rule-challenges-conclusion, and
(2) reports no finding, under any rule, for the closing line `Version 3.2 ships on 14 January
with the streaming parser enabled by default.` Saying that line is specific and fine passes.
FAIL if line 5 is not reported under rule-challenges-conclusion, or if the Version 3.2 line is
reported as a finding under any rule (a generic-conclusion, challenges or other tell).
