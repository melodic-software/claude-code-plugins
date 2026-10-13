---
type: llm
arm: both
---

PASS only if all of these hold:

1. The reply restates the Q2 answer in its own words (not a quotation of the user's reply) and
   says it understood "fee chair flag" as a feature flag, with the flag on for staff first.
2. The reply restates the Q3 answer (local storage instead of the user profile) in its own words.
3. The reply asks the user to confirm Q2 and Q3, or to correct them, before treating them as
   settled.

Q1 may be accepted without a confirmation question.

FAIL if the reply records "fee chair" as the answer without saying how it interpreted it, quotes
the user's words back instead of restating them, or treats Q2 and Q3 as settled without asking.
