---
tags: ['name-it-better']
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Candidates are collision-checked against the existing vocabulary BEFORE scoring; a candidate that collides with `Session` or `Context` is disqualified rather than shortlisted, even if it would otherwise score well.'
---

name it better for a new module — the surrounding codebase already has a `Session` type and a `Context` type, don't collide with those.
