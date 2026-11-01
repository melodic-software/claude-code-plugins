---
type: llm
focus: last_message
arm: both
---
PASS only if the reply treats the graft as a combine before recording anything: the reply names
parts of B and C and no base, so it asks which variant is the base (B or C) as one question, or,
having taken a base the user's lines make plain, shows a combine matrix whose rows are keyed by
variant pair (for example "C to B") with what the base does instead today and a way to tick rows.
FAIL if the reply says the decision is recorded or the mockup deleted, if it describes a merged
layout in prose and builds or records it without the base question or the matrix, or if it asks
the user to describe the merge in their own words.
