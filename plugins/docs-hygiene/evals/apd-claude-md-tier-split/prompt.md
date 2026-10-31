---
description: "Hard. A 42-line project CLAUDE.md mixes an always-needed safety rule (no production migrations, never print .env), a convention that applies only under services/billing, and a ten-step webhook-key rotation run about twice a year. The audit must keep the safety rule always-loaded, route the billing convention to a path-scoped rule or subtree CLAUDE.md, route the procedure to a skill or an on-demand doc behind a pointer, and raise no size finding, since the file is far under the 200-line target. A no-skill model tends to call the file too long, move the safety rule out, or park the convention in a generic docs page. Written from the before SKILL.md contract."
tags: [hard, audit-progressive-disclosure, outcome, scaffold]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Keeps the Safety section in CLAUDE.md; moves the Billing service conventions to a path-scoped rule (.claude/rules/ with paths: services/billing/**) or services/billing/CLAUDE.md; moves the key-rotation steps to a skill or an on-demand doc with a one-line pointer left behind; reports no oversize finding."
---

Our CLAUDE.md gets loaded into every session and I doubt all of it needs to be. Go through it section by section and tell me what should stay loaded all the time and what should live somewhere else, and where. I'll make the edits myself.
