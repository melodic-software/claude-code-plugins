---
description: "Post-mortem is the record first; the interactive view is offered once and built only from JSON by the checked-in builder"
tags: [debug, converted]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Writes the post-mortem as the record first, then offers the interactive view in one sentence, built only with build-view.mjs from redacted JSON data, publish destination from the medium cascade key, and builds nothing before the reader accepts"
---

/debugging:debug is finished: checkout timed out for orders over $1k, the cause was an unbounded retry in the pricing client, and the fix and regression test are in. I would like to click through the hypotheses rather than read the post-mortem.
