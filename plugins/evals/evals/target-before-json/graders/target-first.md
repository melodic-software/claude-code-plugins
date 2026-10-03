---
type: llm
arm: both
---

PASS if the answer gives a corrected command with the target before `--json` (for example `claude plugin eval ./plugins/notes --json results.json`). Explaining that `--json` took the following words as its value is welcome but not required.

FAIL if the command keeps a list-taking flag (`--json`, `--tag`, `--allow-tools`) before the target; drops `--json`; no corrected command is given; the answer blames something else as the real cause (the file name, quoting, a stale CLI) or says either order works; or it later contradicts or retracts the fix.
