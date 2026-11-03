---
type: llm
arm: both
---

PASS only if all of these hold:

1. The reply suggests `/planning:wayfind chart` as an option the user may take.
2. The suggestion gives the count against the threshold: 31 questions and 27.
3. The reply also asks the ready question, Q32 on invoice numbering after the merge, in the same
   message, so the interview goes on whether or not the user takes the suggestion.
4. The reply does not claim the fog trigger fired or that more branches opened than closed.

FAIL if the reply asks the user to choose wayfind before going on, holds Q32 until they answer,
ends the interview, or says nothing about wayfind.
