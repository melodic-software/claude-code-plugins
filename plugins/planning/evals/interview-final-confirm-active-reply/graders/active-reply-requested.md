---
type: llm
arm: both
---

Judge only the request that closes the restatement.

PASS only if the reply asks the user to give an active answer: to confirm the contract, or to name
the numbers (or ids) of the items they want changed.

FAIL if the closing request is a yes/no check such as "Sound good?", "Does this look right?",
"Any thoughts?" or "OK?", or if the reply asks for no confirmation at all.
