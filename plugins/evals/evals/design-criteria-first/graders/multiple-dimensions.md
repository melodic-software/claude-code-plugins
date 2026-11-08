---
type: llm
arm: both
---

Expectation: "Asks about more than one criteria dimension rather than only task fidelity"

PASS if the criteria step covers at least two distinct dimensions, as proposed criteria or as questions to the user: task fidelity (correct, complete drafts) plus at least one other, such as tone or style, privacy, latency, price, consistency or context use.

FAIL if every proposed criterion and every question concerns only task fidelity, or if there is no criteria step.

Example PASS: "Proposed: 90% of drafts correct against a per-email rubric, and tone averaging 4 of 5 or better." Example FAIL: "What share of drafts must answer every question correctly? Would 90% do?"
