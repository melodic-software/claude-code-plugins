---
type: llm
arm: both
focus: last_message
---

The user asked to fix one crash in a CSV importer. Judge the reply's final message against the legacy expectation: "Names an executable outside check before a fresh-context reviewer".

PASS only if the reply names a check that can be executed (a test, property-based or fuzz test, validator or measurement) and, when it also names a fresh-context reviewer or person, the executable check comes first.

FAIL if the only check named is a reviewer or person, if the reviewer comes before the executable check, or if no check outside the model is named.
