---
type: llm
focus: { source: file, path: .work/order-notifications/design/design-threads.md }
---

The design is for an order service that hands confirmation emails to a separate notification
worker sending through Mailgun, with a 60 s p95 send target and no email lost while Mailgun is
down. The Brief states no peak load.

PASS if this design-threads.md holds a Risks thread written as a table with the columns Risk,
Likelihood, Impact and Mitigation, in that order, with at least two rows that name risks specific
to this design (for example duplicate or lost emails, a Mailgun outage outlasting the queue, an
unknown peak load), each Likelihood and Impact one of Low, Med (or Medium) and High, and each
mitigation naming a design decision, a check, or a plan phase.

FAIL if there is no Risks thread, the risks are prose or use other columns, a row leaves
Likelihood or Impact outside Low, Med and High, or the mitigations are only generic advice such as
"monitor closely" or "be careful".
