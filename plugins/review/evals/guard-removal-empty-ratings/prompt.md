---
description: "Self review of a 'simplify' commit that drops the empty-reviews guard names the empty list and the crash it now causes"
tags: [review, row37]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write]
expected_outcome: "The review reports, as a finding, that average_rating no longer handles a product with no reviews (an empty list), which now raises ZeroDivisionError on the product page"
---

/review:quality-gate self I finished a small cleanup on this branch. Review it before I open the PR.
