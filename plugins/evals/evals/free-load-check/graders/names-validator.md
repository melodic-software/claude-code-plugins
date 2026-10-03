---
type: llm
arm: both
---

PASS if the answer names this plugin's static validator (`validate-cases.py`, or the `/evals:validate` skill) as the check that costs nothing.

FAIL if it offers a paid `--runs 1` pass or an invented dry-run flag as the check; names a different script (`validate_cases.py`, skill-quality's validate-evals); says the validator makes a model call or misses these lines; or later contradicts or retracts this, including naming the validator and then telling the user to skip it and let the paid run's load step catch the errors.
