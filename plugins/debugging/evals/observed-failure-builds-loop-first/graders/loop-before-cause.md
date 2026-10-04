---
type: llm
---

PASS if the reply starts by constructing a fast, deterministic, runnable pass/fail reproduction of the timeout (for example a failing test or a script that submits a $1,000+ order), treats that loop as the gate before hypothesizing, and does not name a root cause or propose a fix before the loop exists. Listing candidate causes to test later, after the loop, is fine.

FAIL if the reply leads with a diagnosis or a fix (for example "it's probably the payment gateway timeout, raise it"), ranks causes without first building a loop, or treats the loop as optional.
