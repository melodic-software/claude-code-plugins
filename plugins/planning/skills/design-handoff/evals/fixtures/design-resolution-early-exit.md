---
outcome: early-exit
tier: B
reason: light design, one new value type and a localized contract tweak
---

# Design resolution: slug-normalizer

The change adds a `TopicSlug` value type and moves the existing kebab-case normalization behind it.
Two files change and no module boundary moves, so the full design-threads exploration was not run.

Mechanism: normalization stays a pure function on the value type (trim, lowercase, collapse
separators, truncate to 40 characters), so it can be unit-tested without a fixture tree.

Rationale for the early exit: the shape was already settled by the existing helper's behavior, and
the only open question was where the invariant should live rather than what it should be. Recording
one value type is cheaper than reopening the topology.
