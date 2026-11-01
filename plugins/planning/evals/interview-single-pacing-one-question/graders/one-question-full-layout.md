---
type: llm
arm: both
focus: last_message
---

PASS only if all of these hold:

1. The reply asks exactly one question, and it is one of the five frontier decisions (attempt
   count, delay, what happens after the last attempt, who is alerted, what an alert message
   includes).
2. That question is in the full layout: a context block, a recommendation with its `Basis:` line,
   and its alternatives.
3. The reply ends with a closing probe inviting something that would change the recommendation,
   and then stops for the answer.
4. The reply has no topic header and no index table, and it does not list, preview or number the
   other four decisions as questions to answer now.

FAIL if the reply asks two or more of the decisions, asks one and lists the others for the user to
answer in the same reply, adds an index table, or drops the recommendation, basis or alternatives
from the one question.
