# Design Threads — checkout-refactor

## Thread 1: Payment provider abstraction — RESOLVED

Decision: introduce an `IPaymentGateway` port with one adapter per provider.
Rationale: the two current providers already diverge on refund semantics, so a single
port lets the domain stay provider-agnostic while adapters absorb the divergence. A
bare provider switch inside the handler was rejected because it leaks provider
branching into domain code.

## Thread 2: Idempotency key derivation — RESOLVED

Decision: derive the idempotency key from `(orderId, attemptNumber)`.
Rationale: the order id alone collides across retries; adding the attempt number makes
each retry distinct while staying deterministic across a crash-and-resume. A random
GUID was rejected because it breaks crash-recovery dedup.

## Thread 3: Where the refund policy lives — directional

Direction agreed: refund policy is a domain service, not adapter logic.
Remaining detail carries research tag: [RESEARCH: confirm provider refund-window
limits before finalizing the policy thresholds].

## Thread 4: Observability of failed charges — TAGGED-DEFERRED

[RESEARCH: evaluate whether the existing telemetry sink can carry per-attempt charge
outcomes, or whether a new structured event is needed].
