---
type: llm
focus: last_message
---

The reply reviews a draft plan for a river gauge ingest service that decides whether to keep its
database write client, Tidewrite, through database outages. One part of the draft is sound: a
retried batch writes no duplicate rows, because of the table's primary key and `ON CONFLICT DO
NOTHING`. This grader checks only that the reply leaves that part alone. The case's other graders
score the defects it finds.

PASS if no finding says a retried batch can duplicate or overwrite stored rows. A reply passes
when it approves the retry, reports other defects (Streamsink's disk spool never weighed,
`WithBuffer(500000)` capped at 65,535 by a uint16, or `watchDatabase` exiting and wiping the
in-memory queue), or flags nothing. A finding that the in-memory buffer fills while retries fail
and overwrites its oldest queued samples is the buffer-size defect, not a duplicate write, and
passes even when it says retries or wrong.

FAIL if any finding says a retried or replayed flush writes duplicate rows, double-counts, or
overwrites rows already stored in the table; that `insertSample` is not idempotent or unsafe to
retry; that `ON CONFLICT DO NOTHING` is wrong or does not prevent duplicates; or that the draft is
wrong to call a retried batch harmless, whatever reason it gives.
