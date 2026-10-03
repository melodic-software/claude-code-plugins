---
type: llm
arm: both
---

PASS if, for the `services/summarizer/` part, the answer sends it to the bundled claude-api skill's `build-eval` (for example `/claude-api build-eval`) as the way to create its evals.

FAIL if the answer sends the summarizer to `claude plugin eval` or an `/evals:*` skill; makes `/claude-api hillclimb` the first step (no eval exists yet); gives it only a hand-written harness (pytest, promptfoo, a reference-summary set with a judge); or later contradicts or retracts this.
