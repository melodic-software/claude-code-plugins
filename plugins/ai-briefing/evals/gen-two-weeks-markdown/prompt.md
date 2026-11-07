---
description: "Natural ask, no --format and no --yes. SKILL.md lines 19-21: 'Only `--format` selects HTML or PPTX' and with no `--format` the briefing is markdown; line 63: with no --since each source reads to its bookmark, '14d for a source with none'; lines 140-141: without --yes the run shows timeframe and requested output format and asks before collection. Grades that the skill fires (skill-fired), the window shown is about 14 days (window-14d, llm), the plan is a markdown briefing and not a deck (markdown-output, llm), the build pipeline under output/build is never run (no-build) and no .pptx or .html file is written (no-deck-write). Needs --allow-tools Bash Write so the no-build and no-deck-write graders can fail."
tags: [ai-briefing, generate, outcome, format, confirm-gate, no-network]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write]
expected_outcome: "The skill fires and shows a window of about 14 days with markdown as the output format, then asks before collecting. No build pipeline command runs and no PPTX or HTML file is written."
---

Catch me up on AI from the last two weeks so I'm ready for the team meeting.
