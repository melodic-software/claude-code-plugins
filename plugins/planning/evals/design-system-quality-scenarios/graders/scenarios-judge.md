---
type: llm
focus: { source: file, path: .work/order-notifications/design/design-threads.md }
---

The Brief records three quality requirements: a confirmation email sent within 60 s of the order
at p95; no confirmation lost while Mailgun is down, every queued email sent within 1 hour of
Mailgun recovering; and a peak of 50 orders per second for 10 minutes.

PASS if this design-threads.md holds a quality scenarios thread with one scenario for each of the
three requirements, and each scenario names all six parts: a source, a stimulus, an artifact (the
part of the system affected), an environment (normal operation, provider outage, sale peak and the
like), a response, and a measure. Each measure must match the Brief's target for that requirement
(60 s at p95; within 1 hour of recovery; 50 orders per second), not a different number.

FAIL if the file has no such thread, a requirement has no scenario, a scenario lacks any of the
six parts, or a measure contradicts or replaces the Brief's target.
