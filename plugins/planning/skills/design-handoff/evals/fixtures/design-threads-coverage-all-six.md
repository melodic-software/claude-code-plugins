# Design Threads: notification-fanout

## Thread 1: What we are building. The fanout service boundary. RESOLVED

Decision: a single `NotificationFanout` service that accepts one domain event and emits one message
per subscribed channel.
Rationale: the three callers already duplicate per-channel branching, and folding it into one
service removes that duplication without changing any caller's contract.

## Thread 2: Fanout mechanism. RESOLVED

Decision: a bounded worker pool reading from a durable queue, one message per channel per event.
Rationale: a synchronous loop inside the request path was rejected because a slow channel provider
would then stall the caller's write; the queue absorbs provider latency.

## Thread 3: Runtime placement and topology. directional

Direction agreed: the workers run as a separate deployable alongside the API rather than in-process.
Remaining detail carries research tag: [RESEARCH: confirm the cluster's per-namespace pod budget
before fixing the worker replica count].

## Thread 4: Who owns and operates the service. RESOLVED

Decision: the platform team owns the deployable; the calling product teams own their channel
templates and are the only actors that register a subscription.
Rationale: template churn is product-paced while the transport is platform-paced, so splitting
ownership at that seam keeps each change in one team's hands.

## Thread 5: Timing, sequencing, and lifecycle. directional

Direction agreed: per-subscriber ordering is preserved, global ordering is not, and a message is
retired after the provider acknowledges it or after five failed attempts.
Remaining detail carries research tag: [RESEARCH: measure the observed retry window per provider
before fixing the backoff schedule].

## Thread 6: Why this shape rather than the incumbent. RESOLVED

Decision: keep the existing outbox rather than adopting the provider's own broadcast API.
Rationale: the outbox already gives us at-least-once delivery and a replayable audit trail, and the
provider's broadcast API offers neither; the recorded tradeoff is one extra hop for durability we
would otherwise have to rebuild.
