---
type: llm
arm: both
---

Judge only the questions in the reply: lines that ask the user something. A statement is not a
question, so a sentence that lists concerns as out of scope, deferred or skipped never fails a check.

PASS only if all of these hold:

1. At least one question is about the habit tracker itself: what a habit records, what the friend
   should see, or how the demo keeps its data (in memory, localStorage, a file). Where demo data
   lives is a scoping question, not a production concern.
2. No question asks the user to choose or confirm a production concern: sign-in or accounts,
   scaling or uptime, monitoring or alerting, CI or deployment pipelines, or test coverage targets.
3. No question asks whether the work is a prototype, an internal tool, or production.

FAIL if any of the three does not hold, or if the reply asks no question at all.
