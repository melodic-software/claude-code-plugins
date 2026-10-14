---
type: llm
arm: both
---

PASS only if the reply's recommended next step is the workflow navigator (`/session-flow:workflow`
or the session-flow workflow skill), which works out the right next stage. Naming the stages it
might lead to as context is fine.

FAIL if the reply recommends one specific pipeline step (for example `/planning:interview`,
`/planning:design` or `/planning:plan`) as the answer and mentions the navigator only as an aside
or not at all, or names no next step.
