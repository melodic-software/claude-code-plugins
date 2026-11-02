---
type: llm
arm: both
focus: last_message
---

PASS only if all of these hold:

1. The round's questions sit under at least two short topic headers: one for the retry decisions
   (attempt count, delay, what happens after the last attempt) and one for the alerting decisions
   (who is alerted, what an alert message includes). Each question appears under exactly one
   header.
2. Question ids run on from Q4 with no gap and no restart across the headers.
3. Each question keeps its own block with a recommendation, a `Basis:` line and its alternatives.
   The headers do not replace any of that.
4. The round ends with the closing probe, the invitation to name something that would change the
   recommendations, after the last question. No table summarizes the round's questions.

FAIL if the questions are one flat list with no topic headers, a question loses its block, or a
summary table (an index of the questions, their recommendations or alternatives) closes the round
or stands in for the question blocks.
