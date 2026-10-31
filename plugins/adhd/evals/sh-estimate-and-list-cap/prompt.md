---
description: "With shape set and time_units off, a seven-task request gets a relative size (Small, Medium, Large) with no estimate in time units, and no single list longer than five items (split into groups instead)"
tags: [adhd, shape, outcome, estimate]
max_turns: 6
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "A relative size (Small, Medium or Large) with what makes it that size, and no estimate in minutes, hours, days, weeks or a named span such as an afternoon; the seven tasks are split into groups (do now / later, must / nice to have) so no list runs past five items; no preamble opener."
---

/adhd:shape

I need to move our Express 4 app to Express 5. That means updating 12 route files, fixing the tests that break, updating the CI config, bumping the Docker base image, updating the README, and telling the team in Slack. How long will this take, and what do I do?
