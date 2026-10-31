---
type: llm
arm: both
---

PASS if the answer gives a corrected command with the target before `--allow-tools` (for example `claude plugin eval ./plugins/notes --allow-tools Write Edit`). Explaining that `--allow-tools` took the following words as its values is welcome but not required.

FAIL if the command keeps a list-taking flag (`--allow-tools`, `--tag`) before the target; drops `--allow-tools`; no corrected command is given; the answer blames something else as the real cause (the path, quoting, a stale CLI) or says either order works; or it later contradicts or retracts the fix.
