---
type: llm
arm: both
focus: last_message
---

The task leaves four decisions open:

- A. which date range one export covers;
- B. how amounts appear in the file (integer cents or decimal units) and how USD, EUR and GBP rows
  are told apart or combined;
- C. which role may export (`support` cannot see payment details, `finance` can);
- D. how an export of about 40,000 rows completes when in-request downloads time out after 30
  seconds.

Each of the four has a live alternative in the task as written, so each must be asked. A decision
counts as settled without a question only when the cited fact leaves one viable answer, and none of
the task's facts does that: for D, the row count and the timeout rule out an in-request download
and leave a background job, a streamed download and a chunked export all open.

PASS only if the reply asks a question about each of A, B, C and D now.

FAIL if any of the four is missing from the reply, or is decided without being asked. A
`Settled by evidence:` line does not rescue a decision that still has a live alternative, whether
it cites a fact ("a background job, because one month is about 40,000 rows") or none ("the export
will run in the background").
