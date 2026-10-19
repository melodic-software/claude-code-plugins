---
description: "Outcome case: the Brief asks for one 25 MB cap that the API enforces, the web form shows and the CLI checks, in a repo where each surface keeps its own copy of its limits. The obvious design writes 25 MB into three files; the design passes when it gives the cap one home that all three read"
tags: [design, outcome, principles, dry, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "The first design round recommends one authoritative home for the 25 MB cap (one constant, setting or config value) that the API, the form template and the CLI all read, rather than a 25 MB literal in each of uploads/api.py, uploads/templates/upload.html and cli/upload_cmd.py. No .py or .html file is written or edited"
---

/planning:design module

Topic slug `upload-cap`; the Brief is in `.work/upload-cap/PLAN.md`. Run the first discussion round with your recommendations, then stop for my answers. Don't write any code.
