---
tags: [plan-stress-test]
runs: 3
max_turns: 40
timeout_seconds: 1500
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
---

/planning:plan Continue the draft at `.work/review-target/PLAN.md` from Step 3. The Brief and the design gate are settled; `.work/review-target/design/design-resolution.md` records the design early exit. Run Steps 3, 3b and 4 as this skill and this repository's settings say. Then list every finding you verified as one bullet, naming the file, phase or claim it concerns and saying what is wrong. Stop there: no Step 4.5 onward, and edit no file.
