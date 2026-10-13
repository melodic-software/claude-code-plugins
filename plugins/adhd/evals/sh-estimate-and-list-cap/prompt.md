---
description: "With shape set, a seven-task request gets a concrete time estimate in real units and no single list longer than five items (split into groups instead)"
tags: [adhd, shape, outcome, estimate]
max_turns: 6
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "A time estimate with a number and a real unit (hours, days) or a named span (an afternoon, a day), not 'some work' or 'it depends' alone; the seven tasks are split into groups (do now / later, must / nice to have) so no list runs past five items; no preamble opener."
---

/adhd:shape

I need to move our Express 4 app to Express 5. That means updating 12 route files, fixing the tests that break, updating the CI config, bumping the Docker base image, updating the README, and telling the team in Slack. How long will this take, and what do I do?
