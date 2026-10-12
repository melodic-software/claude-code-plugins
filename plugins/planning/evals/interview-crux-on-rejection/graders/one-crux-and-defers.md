---
type: llm
arm: both
---

PASS only if all of these hold:

1. For Q2 the reply asks one question aimed at what would have to be true for Kafka, or for the
   Postgres queue, to be the right choice (for example a need Kafka meets that the user knows of,
   such as other consumers or replay), or it proposes one concrete check that would settle it. It
   does not argue for Postgres more than once, and it accepts Kafka if the user holds to it.
2. For Q3 the reply accepts `ship-docs` as the user's choice without arguing for `docs-publish`.
3. Q1 is accepted.

FAIL if the reply re-argues the Postgres recommendation at length or more than once, challenges
the `ship-docs` name, or records Kafka with no question or check at all.
