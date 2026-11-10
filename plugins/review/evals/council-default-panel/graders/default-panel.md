---
type: llm
arm: both
---

PASS if the answer says three members run, briefed correctness, design and adversarial; each runs on Opus as the review plugin's brief-reviewer agent; one round runs; and scores (marks) are off, so the report has no mark table.

FAIL if the answer names a different member count or set of briefs, a model other than Opus for these defaults (Fable included), a different agent, more than one round, or scores on; or if it says nothing runs without configuration.
