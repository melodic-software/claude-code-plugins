---
type: llm
arm: both
---

PASS if the answer's `noise-report.py` command passes the run's threshold (`--threshold 0.8`; 0.80 and .8 are the same) and `--grader-agreement`. Stating the condition under which `--grader-agreement` applies (the plugin's grader-run-twice setting, on by default) is fine.

FAIL if either flag is missing, the threshold has another value, or the answer later says to drop either.
