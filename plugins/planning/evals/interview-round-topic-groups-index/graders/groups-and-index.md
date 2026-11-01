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
   The headers and the index do not replace any of that.
4. After the last question, one table has the columns Q, Recommendation, Basis and Main
   alternative, with one row per question asked in the round. Each Q cell carries the id with a
   plain name (such as "Q4, attempt count"), and each row's recommendation says the same thing as
   the recommendation in that question's block.
5. The closing probe, the invitation to name something that would change the recommendations,
   comes after the index table.

FAIL if the questions are one flat list with no topic headers, the index table is missing or
leaves out a question that was asked, the index stands in for the question blocks, or the closing
probe comes before the index.
