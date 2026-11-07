---
description: "Legacy clarify 7. Cold start: the session has no prior assistant message, so 'make this clear' has no target; the skill asks what to clarify and invents none (SKILL.md lines 21 and 33-34). asks-what-to-clarify needs a question about the target; no-invented-target fails a decision table, a 'What you're deciding' column, a Left out note or a lens line, which only a restructure of an invented target would carry. skill-fired is a with-only indicator."
tags: [adhd, clarify, outcome, cold-start, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "One or two lines saying there is nothing to clarify yet and asking what to clarify; no table, no Left out note, no lens line."
---

make this clear
