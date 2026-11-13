---
type: llm
arm: both
---

PASS only if the reply (1) reads item #812 through `/work-items:track view` with `--comments`,
not a `gh` or other provider command; (2) takes the decisions from the closing comment that states
them, not from the close summary that follows it; and (3) carries Q2, Q4 and Q5 into the PRD (the
primary user, no email alerts in v1 as a non-goal, the 30% within 30 days metric) without asking
any of them again.

FAIL if the reply asks the user any of Q2, Q4 or Q5, reads the tracker with a provider command,
treats the close summary as the decisions, or carries none of the three decisions.
