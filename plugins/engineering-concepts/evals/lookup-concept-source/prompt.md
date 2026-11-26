---
description: "Triggering case for engineering-concepts:lookup. The request asks the built-in engineering-concept catalog for a concept's official source and counterweights, the description's main use. The plugin ships no curated records yet, so the answer is not graded; the grader reads only the Skill call."
tags: [engineering-concepts, lookup, triggering]
max_turns: 8
timeout_seconds: 240
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "A Skill call loads engineering-concepts:lookup."
---

Check the engineering-concepts catalog for the single responsibility principle: what is its official source, and which concepts does the catalog list as its counterweights?
