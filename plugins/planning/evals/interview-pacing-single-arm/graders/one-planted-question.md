---
type: llm
arm: both
focus: last_message
---

The task leaves four decisions open: A, which date range one export covers; B, how amounts appear
(integer cents or decimal units) and how USD, EUR and GBP rows are told apart or combined; C,
which role may export; D, how an export of about 40,000 rows completes when in-request downloads
time out after 30 seconds.

PASS only if the reply asks exactly one question, that question is about one of A, B, C or D, and
the reply has no topic header, no index table, and no list, preview or numbering of the other
decisions as questions to answer now. A `Settled by evidence:`, `Held:` or `Later:` line naming
other decisions is allowed: it records them, and asks nothing. The closing probe at the end ("Is there something else that would
change this recommendation?") is not a question for this count.

FAIL if the reply asks two or more questions, asks one and lists the others for the user to answer
in the same reply, or asks about something other than A, B, C or D.
