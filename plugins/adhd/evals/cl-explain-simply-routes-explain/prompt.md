---
description: "Legacy clarify 4, its prompt verbatim behind /adhd:clarify. The skill description routes a plain-language ask away from this skill (SKILL.md line 2), so a natural prompt never loads the body whose routing (lines 192-196) the legacy expectations grade; the slash form loads it, which is what the legacy run graded. History: the previous assistant message is the dense Round 4 (Q12 to Q15). 'explain this simply' asks for an altitude drop, which is education:explain's lane (SKILL.md lines 179-180, 192-196); only the plugin under test loads, so the skill names that lane and, if it acts, restructures without lowering altitude. names-explain-lane needs the lane named; no-diagram fails a mermaid, svg or box-drawing diagram; altitude-held (llm) quotes the four legacy expectations. A history_file case runs single-arm on a path target; pass --ablation with-without to compare."
tags: [adhd, clarify, outcome, boundary, history, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "Names education:explain as the skill a plain-language ask wants, draws no diagram, and either stops there or restructures Round 4 with every operative term and the reading level unchanged."
---

/adhd:clarify explain this simply, I don't get what the previous message means
