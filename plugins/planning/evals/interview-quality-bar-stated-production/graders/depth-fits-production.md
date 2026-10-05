---
type: llm
arm: both
---

PASS only if all of these hold:

1. The reply asks at least one scoping question about the export itself (which accounting systems, which invoices, the export format, or the schedule).
2. At least one question in the reply covers a production concern for a service customers rely on: what happens when an export fails or partially fails, retries or idempotency, data correctness or reconciliation, credential or data security, monitoring or alerting, or rollback.
3. The reply does not ask whether the work is a prototype, an internal tool, or production.

FAIL if any of the three does not hold, or if the reply asks no question at all.
