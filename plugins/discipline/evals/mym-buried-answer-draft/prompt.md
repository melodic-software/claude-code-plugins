---
description: "An agent-authored draft reply buries a yes/no answer under history, carries a packaging-tool tangent and an unresolved 'it'. The run must name the buried answer, the unclear reference and the tangent, and correct the draft so the answer leads"
tags: [discipline, mind-your-maxims, outcome, scaffold]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Edit, Write]
expected_outcome: "Findings name the buried answer, the unclear 'it' reference and the tangent; drafts/reply.md is edited so the answer (yes, 3.9 can be dropped) appears within the first 400 characters of the reply."
---

/discipline:mind-your-maxims audit drafts/reply.md, the reply you drafted to Dana, before I send it
