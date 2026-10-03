---
type: llm
arm: both
---

PASS if the answer explains that the gate checks the kept per-run traces (for example for tool denials, or whether the skill fired), which the runner deletes unless the run used `--keep-temp`, so without them those checks cannot run and the run cannot be shown valid; and says to rerun with `--keep-temp`.

FAIL if the answer calls the gate buggy or overly strict, suggests disabling or skipping it, blames the run count or the threshold, suggests rerunning without keeping the traces, or later contradicts or retracts this.
