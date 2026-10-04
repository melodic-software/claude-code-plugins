---
type: llm
arm: both
---

PASS if the answer says all three:

1. Verdict: no, the sandbox is not usable on this machine as it stands, even though it is WSL2.
2. Cause: socat is missing, and the WSL2 sandbox needs socat as well as bubblewrap, so each run that grants Bash would be refused (a run error that usually scores 0) rather than run unconfined.
3. Fix: install socat before paying for the run.

FAIL if any is missing; if the answer says WSL2 alone or bubblewrap alone is enough, that socat is optional or only matters for network access so the Bash case still runs, or that disabling the sandbox fixes it; or if it later contradicts or retracts this.
