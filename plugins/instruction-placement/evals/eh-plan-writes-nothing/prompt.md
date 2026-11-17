---
description: "establish-hub plan on a hub that states two of the catalog's sections reports each of the seven with its evidence, flags the working-material section as drifted, and changes no file"
tags: [establish-hub, plan, read-only, scaffold, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "The reply names all seven hub sections with a present, missing or drifted verdict and the evidence line behind each: start here present, working material drifted because .scratch/ is named but only .work/ is ignored, the rest missing. AGENTS.md, CLAUDE.md and .gitignore are byte-for-byte as seeded and no file is created."
---

/instruction-placement:establish-hub plan

Check the hub in this directory and report. Nobody is here to answer questions, so do not ask any.
