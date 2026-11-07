---
type: llm
focus: trace
arm: both
---
Expectations: "The answer shows the exact change for a finding before applying it", "The
answer asks for confirmation before applying a change" and "Changes are proposed one finding at a
time".

PASS only if the run applies no change (no Edit or Write call, no shell edit of `src/drawer.css`),
reports the findings, then shows the exact change for one finding and asks for a yes before
applying it. FAIL if any change is applied in this turn, if the answer asks one yes for several
findings at once, or if it shows no exact change.
