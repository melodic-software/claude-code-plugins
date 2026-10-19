---
description: "Production integration design for a partner webhook whose payload partners build against: the first round calls the payload contract a one-way door and prompts for an ADR, and writes no code"
tags: [design, reversibility, one-way-door, adr, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "The first design round classes the order.shipped payload shape (a contract partners build against) as a one-way door and prompts for an architecture decision record, for example by offering /architecture:record-decision once the thread resolves. No .py file is written or edited"
---

/planning:design integration

Topic slug `shipped-webhook`; the Brief is in `.work/shipped-webhook/PLAN.md`. Run the first discussion round with your recommendations, then stop for my answers. Don't write any code.
