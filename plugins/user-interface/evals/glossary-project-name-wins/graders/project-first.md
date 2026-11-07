---
type: llm
arm: both
---
Expectations: "The answer leads with Notice, the project's name for the thing", "The answer
defines the toast as a temporary notification that dismisses itself" and "The answer does not tell
the user to rename Notice to toast".

PASS only if the reply leads with Notice, gives toast beside it defined as a temporary notification
that dismisses itself, and does not tell the user to rename Notice to toast. FAIL if it leads with
toast, gives no self-dismissing definition, or suggests renaming.
