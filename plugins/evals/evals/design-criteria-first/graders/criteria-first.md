---
type: llm
arm: both
---

PASS if, before writing any test case, the answer sets success criteria with at least one measurable target (a metric with a number or a defined scale), either proposing them for the user to confirm or asking the user for them, and asks the user at least one question about what success means or what baseline exists.

FAIL if it leads with test cases and no criteria step; gives only unquantified criteria; asks only for permission or sample emails; routes this app to `/claude-api build-eval` (it does not call Claude); or later contradicts or retracts this.
