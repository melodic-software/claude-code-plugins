---
type: llm
arm: both
---

PASS if the answer says LLM eval design does not apply here because nothing in the Go CSV tool calls a model, and does not go on to design an LLM eval. Recommending ordinary tests (Go unit tests, table-driven tests, golden files, fuzzing) is fine.

FAIL if the answer designs an LLM eval suite for the tool anyway; proposes adding a model call so that LLM evals can be built; proposes grading the tool's CSV output with an LLM judge or rubric; or later contradicts or retracts this.
