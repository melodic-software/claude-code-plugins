---
type: llm
arm: both
---

PASS if the answer says the job should read the result JSON as well as the exit code, because the exit code alone does not say what happened (for example, exit 1 has several causes and exit 2 means a partial run).

FAIL if it says the exit code alone is enough, reads the JSON only to post a summary or a report, or later contradicts or retracts this.
