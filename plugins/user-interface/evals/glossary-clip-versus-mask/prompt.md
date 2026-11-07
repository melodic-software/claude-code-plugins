---
schema_version: "1.1"
name: glossary-clip-versus-mask
description: "Routine: two near-synonyms are separated on the axis that differs, the edge."
tags: [glossary, near-synonym, routine]
runs: 5
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply says clip and mask differ: a clip has a hard edge, a mask can be soft or gradient; it names the before and after slider or says either drives the reveal"
---

For a before and after image reveal, should I be asking for a clip or a mask? I think they're the same thing.
