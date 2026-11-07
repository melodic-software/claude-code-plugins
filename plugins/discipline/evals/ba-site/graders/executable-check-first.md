---
type: llm
arm: both
focus: last_message
---

The user made a request. Judge the reply's final message against the legacy expectation: "Names concrete methods and one check outside the model, executable first".

PASS only if the outside check the reply names includes something that can be executed or measured (a test, benchmark, validator, measurement or browser run) and, when the reply also names a person or fresh-context reviewer as a check, the executable check comes first.

FAIL if the only check named is a person or reviewer, if the reviewer is put before the executable check, or if no check outside the model is named.
