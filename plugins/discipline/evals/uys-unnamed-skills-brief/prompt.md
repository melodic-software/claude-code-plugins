---
description: "A drafted subagent brief asks for a copied-content audit that a listed skill owns but names no skill. The run must map the task to the listing and re-issue the brief with that skill named"
tags: [discipline, use-your-skills, outcome, scaffold]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Edit]
expected_outcome: "Reads notes/delegation-brief.md, edits it to name point-dont-copy, and names point-dont-copy in the reply."
---

/discipline:use-your-skills check the brief in notes/delegation-brief.md before I send it to the subagent
