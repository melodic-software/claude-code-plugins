---
type: llm
arm: both
---

Expectation: "Asks for or establishes a baseline for at least one target, or records the target as provisional"

PASS if the answer asks whether a baseline exists (a current edit rate, past scores, any existing measure), proposes recording the first run as the baseline, or marks a target as provisional until a baseline exists.

FAIL if targets are stated with no mention of a baseline, of current performance, or of their being provisional.

Example PASS: "Do you have a baseline, such as how many drafts agents rewrite today, or should the first run set it?" Example FAIL: "Targets: 90% of drafts correct, tone 4 of 5. Now tell me what success means to your team."
