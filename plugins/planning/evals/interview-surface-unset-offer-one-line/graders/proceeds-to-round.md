---
type: llm
arm: with-only
focus: last_message
---

PASS only if all of these hold:

1. One line says where the interview asks and names the other available surfaces together (for
   example `Asking here, one round at a time. A local page is also available; say which to
   switch.`), and no other line repeats or expands that offer.
2. The reply does not ask which surface to use and does not wait for a surface choice: the offer is
   a statement, and the reply goes on to the interview.
3. The reply asks round 1 of the interview about the webhook sender's retries and alerting in the
   conversation: at least one numbered question, open or with a recommendation.

FAIL if the offer is missing, is spread over several lines or a list, is phrased as a question the
user must answer before the interview starts, or if the reply stops before asking round 1.
