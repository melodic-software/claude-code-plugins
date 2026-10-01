---
type: llm
arm: both
---

PASS if the answer's main recommendation for creating this service's first eval suite is the bundled claude-api skill's `build-eval` subcommand (for example `/claude-api build-eval`). Describing what build-eval sets up (labelled inputs, a grader for the label) is fine.

FAIL if build-eval is absent or offered only as an optional extra; if the main route is something else (a hand-written harness, promptfoo, `/claude-api hillclimb`, `claude plugin eval`, or an `/evals:*` skill); if the answer says it has started build-eval; or if it later contradicts or retracts the recommendation.
