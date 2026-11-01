---
type: llm
arm: both
focus: last_message
---

PASS only if all of these hold:

1. The reply takes up the discussion of Q4: it engages the user's concern about a receiver that
   is down for about an hour during a deploy, for example by working out how long five attempts
   with the backoff would span.
2. Q4 is not treated as answered. The reply does not record five, or any other attempt count, as
   the user's answer, and does not settle Q4 at its recommendation.
3. Q5 is recorded as answered with the recommended exponential backoff from 30 seconds.
4. Q6 is named as still open, since the user's reply did not address it.
5. If the reply asks Q4 again, it shows Q4 in the full question layout (context, a recommendation
   with its basis, alternatives) and states the recommendation as revised from old to new with
   the reason, or as unchanged with the reason.

FAIL if Q4 is recorded as answered, Q6 goes unmentioned, or the reply writes a Brief or asks the
user to confirm the whole contract while Q4 or Q6 is unresolved.
