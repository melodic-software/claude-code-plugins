---
type: llm
arm: both
---

PASS only if all of these hold:

1. The reply restates the intent of the work (CSV export of the admin orders page) in a sentence
   or two.
2. It shows the Q5 change: the file name is now orders-export-<timestamp>.csv.
3. It shows both assumptions the sweep added: exports run synchronously in the request, and the
   export respects the user's row-level permissions.
4. It does not re-list the answers that were accepted and read back unchanged (Q1, Q2, Q3, Q4,
   Q6, Q7, Q8). A count of them, or one line saying they stand as read back, is fine.

FAIL if any of the four does not hold.
