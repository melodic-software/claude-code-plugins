---
description: "A repository whose default branch sets verification: light in docs/conventions/event-storming.yaml, with a structured-markdown Big Picture export seeded: simulation-evaluation.md 'How to Run an Evaluation' step 3 reads the level, dispatches no fresh-context scorer, writes the skip token, and leaves every criterion unscored rather than scoring the board itself. Needs --scaffold --allow-tools Bash and a sandbox backend. Host tool: git for the scaffold."
tags: [event-storming, simulation, setting, verification-level, scaffold]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; dispatches no subagent; writes verification: skipped (light); reports the criteria unscored."
---

Use the event-storming simulation skill. I ran a Big Picture simulation in structured-markdown mode, and its board export is ./board-export.md. Run the evaluation step on it against the Big Picture rubric and give me the scores. No Miro is available.
