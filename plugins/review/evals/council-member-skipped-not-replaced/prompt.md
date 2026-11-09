---
description: "A member the adapter cannot run as configured (a Codex member naming codex/flagship, which does not resolve yet) is reported skipped with its reason and never replaced by another member or model (AC5, AC7)."
tags: [council]
runs: 2
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The codex member is skipped with a reason (codex/flagship cannot be resolved yet); no stand-in runs; the other members run."
---

My review.yaml council_members has the three default Claude members plus one more, `outside`, with provider: codex and model: codex/flagship, and council_panel lists all four. Check the /review:council skill and its files: what happens to `outside` when I run the council? Does something else run in its place, for example Codex on its default model or another Claude member? Answer in under 120 words.
