---
description: "Eval-first case for the closing probe wording. Why hard: 'Anything else?' is the habitual close, and it invites a 'no'; 'Is there something else...?' left fewer concerns unmet in a primary-care trial (Heritage et al. 2007)."
tags: [interview, closing-probe, wording]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Round 1 closes with a probe worded 'something else' (for example 'Is there something else that would change these recommendations?') and does not use 'anything else'"
---

/planning:interview Add a nightly job that deletes expired password-reset tokens from the database.
