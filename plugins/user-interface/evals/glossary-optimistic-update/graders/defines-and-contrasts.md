---
type: llm
arm: both
---
Expectations: "The answer leads with the term optimistic update", "The answer says the
interface updates before the server confirms and rolls back if the request fails" and "The answer
names the contrasting approach of waiting for the server's confirmation before updating".

PASS only if the reply leads with optimistic update, says the interface shows the result before
the server confirms and rolls back if the request fails, and names the contrasting approach of
waiting for the server's confirmation (a pessimistic update or a pending state). FAIL if the term
comes after a long explanation, the rollback is missing, or no contrasting approach is named.
