---
type: llm
arm: both
focus: last_message
---

PASS only if all of these hold:

1. Each of the round's questions names its topic in parentheses in its title line, as in
   `Q4 (attempt count): **...**`: the retry decisions (attempt count, delay) and the alerting
   decisions (who is alerted, what an alert message includes) each carry a topic in plain words.
2. No topic header sits over the questions: no heading or bold line such as "Retries" or
   "Alerting" groups them.
3. Question ids run on from Q4 with no gap and no restart.
4. Each question keeps its own block with a recommendation whose reason names its basis, and its
   alternatives. A question whose recommendation is withheld meets the recommendation part with a
   `Withheld:` line that names the evidence that would settle it, and still keeps its
   alternatives.
5. The round ends with the closing probe, the invitation to name something that would change the
   recommendations, after the last question. No table summarizes the round's questions.

FAIL if a question title names no topic, topic headers group the questions, a question loses its
block, or a summary table (an index of the questions, their recommendations or alternatives)
closes the round or stands in for the question blocks.
