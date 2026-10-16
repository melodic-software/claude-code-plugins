---
description: "At Step 5 the hand-off to /verification:confirm names the PLAN.md path, so a fresh confirm session reads the Brief; the prompt never asks for the path."
tags: [intent-r2, implement, completion]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply gives the outcome-verification step as /verification:confirm with .work/late-fee/PLAN.md as its argument."
---

/implementation:implement All three phases of the approved plan at .work/late-fee/PLAN.md are marked [DONE] on branch `feat/late-fee`, the final build and every affected test are green, and the self-review found nothing. In this run do not edit files, run commands or invoke any other skill: go straight to Step 5's hand-off, end with a reply that lists each pre-PR step in order with the exact invocation you would make for it, and stop.
