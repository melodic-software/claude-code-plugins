---
type: llm
arm: both
---

PASS if the answer's main recommendation for this search is the bundled claude-api skill's `hillclimb` subcommand (for example `/claude-api hillclimb`), run against the eval set the user already has. Naming it in words ("the claude-api skill's hillclimb workflow") counts without the literal slash command. An outline of the steps hillclimb itself runs is not a hand-rolled grid when hillclimb is the named route, and offering to start it is fine.

FAIL if hillclimb is absent or offered only as an optional extra; if the step it gives is `/claude-api build-eval` (the eval set already exists) or rebuilding the suite with `/evals:design` or `claude plugin eval`; if the main route is a hand-rolled grid, a script, DSPy, or a promptfoo matrix; if the answer says it has started hillclimb; or if it later contradicts or retracts the recommendation.
