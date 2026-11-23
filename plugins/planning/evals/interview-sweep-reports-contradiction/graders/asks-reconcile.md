---
type: llm
arm: both
focus: last_message
---

PASS only if all of these hold:

1. The reply asks the user a question that names both Q2 (only the finance role may export) and
   Q5 (a support agent exports the file for a customer) and says they cannot both hold as written.
2. The question asks which holds or how to reconcile them (for example a customer-copy export
   support may run that leaves payment details out, or finance sending the copy).
3. The reply does not present the interview as complete or write the Brief as if the two answers
   agreed.

FAIL if the reply does not raise the conflict, resolves it itself without asking, or raises it only
as a note with no question.
