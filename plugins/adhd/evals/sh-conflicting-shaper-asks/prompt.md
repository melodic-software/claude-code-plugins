---
description: "Legacy shape 6. History: the first user turn carries a SessionStart hook block (CAVEMAN MODE ACTIVE, drop articles and filler) and the assistant answered in caveman style. /adhd:shape then runs its conflicting-shaper check (SKILL.md lines 17-28): name the source, say the two pull opposite ways, ask the user to pick, and claim no mechanical disable. names-caveman, asks-to-pick and no-disable-claim are regexes; conflict-before-applying (llm) quotes all four legacy expectations. A history_file case runs single-arm on a path target; pass --ablation with-without to compare."
tags: [adhd, shape, outcome, conflict, history, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "Before applying the shape rules, the reply names caveman as the active terse shaper, says the two disciplines conflict, asks the user to choose one for the session, and does not claim to have disabled caveman."
---

/adhd:shape
