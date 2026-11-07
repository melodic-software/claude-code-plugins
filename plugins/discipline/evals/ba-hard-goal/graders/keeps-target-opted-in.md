---
type: llm
arm: both
focus: last_message
---

The user asked to cut a 4-minute test suite to under 10 seconds and said they opt into that unreasonable target. Judge the reply's final message against the legacy expectation: "Keeps the hard target only because the user opted in".

PASS only if the raised version keeps the under-10-second target the user opted into, not softened to a looser number and not dropped.

FAIL if the reply drops or loosens the target, replaces it with a different goal, or adds a further hard target the user did not opt into.
