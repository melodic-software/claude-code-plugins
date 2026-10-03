---
type: llm
arm: both
---

PASS if the answer says both:

1. Warning: with `--judge-model sonnet` the judge is the same model as the one under test, so the preflight prints a same-model warning advising a different `--judge-model`.
2. Not a refusal: the run still goes ahead; the warning is advice.

FAIL if either is missing; if the answer says the run refuses, blocks, or errors, says no warning is printed, says `--judge-model` does not exist, or says passing `--judge-model sonnet` changes nothing because the judge already follows `--model`; or if it later contradicts or retracts this.
