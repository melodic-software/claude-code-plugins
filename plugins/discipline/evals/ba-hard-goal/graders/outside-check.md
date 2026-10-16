---
type: llm
arm: both
focus: last_message
---

The user made a request. Judge the reply's final message.

PASS only if the reply names at least one specific check outside the model that would show the result is right, saying what it checks: something to execute (a test, benchmark, validator, measurement, browser run) or a person or fresh reviewer who did not produce the work.

FAIL if the only check is the model's own review or confidence ("I double-checked", "this should work"), if checking is mentioned without saying what would be checked, or if there is no check.
