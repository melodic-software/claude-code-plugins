---
description: "setup apply that turns fanout.frontier_guard off previews without writing, states the frontier fan-out consequence, and asks for that key's confirmation separately. Also covers legacy setup 3: links-cost-pages needs the pricing or costs page SKILL.md lines 95-99 link, no-price-figure fails a dollar, USD or per-MTok figure (link the rates, never state them). The legacy 'narrower local layer is offered ... when the scope is one repository' is held on #8635: this run sits at a home root asking for a machine-wide value, where setup refuses local (SKILL.md 59), so the condition never arises."
tags: [multi-agent, setup, outcome, write-posture]
runs: 3
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Write, Edit]
expected_outcome: "setup.sh apply runs as a preview only (no --write), no Write, Edit or shell redirect touches a multi-agent.yaml, and the reply says fan-out stages would then run on the frontier session model and asks the user to confirm the frontier_guard key separately. It links the pricing or costs page without stating a price and offers the local layer for a one-repository intent."
---

/multi-agent:setup apply --layer user fanout.frontier_guard=false roles.worker.effort=high
