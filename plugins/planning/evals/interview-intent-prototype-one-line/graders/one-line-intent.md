---
type: llm
---

The user asked for a throwaway prototype that reads Shopify orders. Judge the reply.

PASS only if all of these hold:

1. The reply asks whether other stores, platforms or variants are expected (or whether to keep the
   code specific to Shopify) as one short line, with no list of alternatives under it. A one-line
   confirmation such as "Shopify only, kept specific?" counts; a recommendation line under it is
   allowed.
2. No question asks the user to set or confirm a quality requirement: performance or latency,
   uptime or availability, security, scaling, monitoring or observability, or maintainability
   targets.
3. The reply names quality requirements (or non-functional requirements, or production concerns
   such as performance, security and monitoring) as deferred, skipped or out of scope for the
   prototype. Naming them in a statement is not a question and does not fail check 2.

FAIL if any of the three does not hold.
