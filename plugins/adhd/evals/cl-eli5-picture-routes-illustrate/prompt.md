---
description: "Legacy clarify 8, its prompt verbatim behind /adhd:clarify. The skill description routes a picture or ELI5 ask away from this skill (SKILL.md line 2), so a natural prompt never loads the body whose routing (lines 192-196) the legacy expectations grade; the slash form loads it, which is what the legacy run graded. History: the previous assistant message is the dense Round 4 (Q12 to Q15). 'ELI5 ... the picture version' asks for a change of medium, education:illustrate's lane (SKILL.md lines 181-182, 192-196). names-illustrate-lane needs that lane named; no-diagram fails a diagram the skill draws itself; lanes-distinct (llm) quotes legacy expectations 1 and 3. Held: legacy expectation 2's 'does not treat the request as a cue to restructure the message instead', since only the plugin under test loads and SKILL.md lines 194-196 then call for a faithful restructure. A history_file case runs single-arm on a path target; pass --ablation with-without to compare."
tags: [adhd, clarify, outcome, boundary, history, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "Names education:illustrate (not education:explain) as the skill a picture or ELI5 ask wants, draws no diagram itself, and keeps structure, prose altitude and visual medium as three lanes."
---

/adhd:clarify ELI5 this, give me the picture version of what the previous message is saying
