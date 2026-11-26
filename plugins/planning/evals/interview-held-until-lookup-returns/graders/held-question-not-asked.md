---
type: llm
arm: both
focus: last_message
---

PASS only if all of these hold:

1. The reply does not ask who is alerted (or which channel alerts go to) as a question to answer
   now, and gives no recommendation for it.
2. It says that question waits for the PagerDuty lookup, on an `Open:` line or an equivalent line in
   the round header.
3. It asks the question about what an alert message includes.

FAIL if the reply asks the who-is-alerted question now (with or without a recommendation), asks
nothing, or stops to wait for the lookup without asking the alert-content question.
