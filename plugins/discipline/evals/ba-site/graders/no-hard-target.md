---
type: llm
arm: both
focus: last_message
---

The user made a request and did not opt into any hard or aggressive target. Judge the reply's final message against the legacy expectation: "States no hard or unreasonable target, since the user did not opt into one".

PASS only if the raised version sets no hard or unreasonable target of its own (for example an extreme load time, score or deadline put forward as the goal to hit).

FAIL if the reply adds such a target to the raised request.
