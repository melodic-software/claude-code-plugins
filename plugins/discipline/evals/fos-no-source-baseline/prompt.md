---
description: "Legacy follow-our-standards 2 (prompt verbatim plus one line naming the change). The scaffold has a short CONTRIBUTING.md, no CLAUDE.md and no standards source, and src/orders.py repeats its tax logic. Graders: skill-fired (with-only), reads-contributing and falls-back (llm) for exp 1, states-baseline-resolved (exp 2), no-fabricated-source (llm, exp 3). Needs --scaffold --allow-tools Edit."
tags: [discipline, follow-our-standards, outcome, scaffold, no-network]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Edit]
expected_outcome: "Reads CONTRIBUTING.md, says the repository's own conventions and the portable baseline resolved, audits src/orders.py against them (the duplicated tax logic), and invents no organization standards repository."
---

follow our standards for this change. (This repo declares no external standards source and has only a short CONTRIBUTING file.) The change is src/orders.py.
