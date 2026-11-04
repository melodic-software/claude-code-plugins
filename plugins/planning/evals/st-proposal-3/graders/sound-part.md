---
type: llm
focus: last_message
---

The reply reviews a draft proposal for a database-backed invoice job queue in a billing service.
One part of the draft is sound: workers poll for jobs every five seconds, because the connection
pooler runs in transaction mode, which leaves no session for LISTEN/NOTIFY. This grader checks
only that the reply leaves polling alone. The case's other graders score the defects it finds.

PASS if no finding says polling is wrong or should be replaced. A reply passes when it approves
polling, reports other defects (the Rollout adding Redis, `createInvoice` not being idempotent, or
a job left in `running` after a killed worker), or flags nothing. A finding that the poll should
also pick up stranded `running` jobs, for example through a lease, fixes that last defect and
passes, as does a finding about the 5-second stop grace period.

FAIL if any finding calls polling wasteful, wrong or a poor choice, or asks to replace the poll
loop with LISTEN/NOTIFY or another notification channel. A finding that quotes the draft's claim
that polling is fine and then rebuts it fails, with or without a contrast word.
