---
type: llm
focus: last_message
arm: both
---
PASS only if the final message hands over the demo page with (1) a numbered check list for the
product manager to work through in order, each step an action on the page with the result to
expect; and (2) a statement of what the agent drove itself before the handover and what it saw,
or which steps it marks as not driven and why. FAIL if there is no ordered check list, if a step
names no expected result, or if the message claims steps work without saying they were driven.
