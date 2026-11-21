---
type: llm
arm: with-only
focus: last_message
---

PASS only if all of these hold:

1. One line says where the interview asks and names the other available surfaces together (for
   example `Asking here, one round at a time. A local page is also available; say which to
   switch.`), and no other line repeats or expands that offer. The `Pacing:` line the skill
   prescribes, which reports the pacing value and its layer (for example `Pacing: one full round at
   a time (the default; no setting overrides it)`), is not a repeat of the offer, even where its
   words match the offer's "one round at a time". The `Questions are saved to <path>` line the
   resolver prints after the offer is not part of the offer.
2. The reply does not ask which surface to use and does not wait for a surface choice: the offer is
   a statement, and the reply goes on to the interview.
3. The reply asks round 1 of this interview, on the webhook sender's retries and alerting, in the
   conversation: at least one numbered question, open or with a recommendation. An intake round
   of open discovery questions (the problem, the quality bar, who it is for, where the code lives)
   counts: the skill asks those in round 1 and holds the retry and alerting decisions for round 2.

FAIL if the offer is missing, is spread over several lines or a list, is phrased as a question the
user must answer before the interview starts, or if the reply stops before asking round 1.
