---
type: llm
arm: both
focus: last_message
---

PASS only if all of these hold for every question the reply asks:

1. It opens with a context block that cites at least one fact the user stated (the calendar-month
   close, integer cents in USD, EUR and GBP, the spreadsheet, the `support` and `finance` roles,
   about 40,000 rows a month, the 30-second request timeout, or a round 1 answer).
2. It gives one recommended answer, or a `Withheld:` line naming the evidence that would settle it.
3. A question with a recommended answer carries a `Basis:` line naming what the recommendation
   rests on. A question with a `Withheld:` line needs no `Basis:` line.
4. It lists at least one alternative.

And the reply ends with a closing probe inviting something that would change the recommendations,
then stops for the answer.

FAIL if any question lacks its context block, its recommendation (or `Withheld:` line), the
`Basis:` line its recommendation needs, or its alternatives, or if the reply has no closing probe.
