---
type: llm
arm: both
---

PASS only if all of these hold:

1. The reply asks at least one scoping question about the habit tracker itself (what a habit is, what the friend should see, where data lives for the demo).
2. No question in the reply asks the user to choose or confirm production-grade concerns: authentication or accounts, scaling, monitoring or alerting, CI or deployment pipelines, test coverage targets, or data migration. Mentioning such a concern only to say it is out of scope for a prototype is fine.
3. The reply does not ask whether the work is a prototype, an internal tool, or production.

FAIL if any of the three does not hold, or if the reply asks no question at all.
