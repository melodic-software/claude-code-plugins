---
description: "Legacy shape 1. A natural 'ADHD-friendly' request with no slash command, so the skill must fire from its description; skill-fired is a with-only indicator. The reply's first line is a concrete action (SKILL.md rule 1), the steps are numbered (rule 2), it ends on one next action (rule 3), and it has no preamble opener or closer (rule 10)."
tags: [adhd, shape, outcome, trigger, action-first, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "The skill fires; the first line is a command, path or imperative; the steps are a numbered list of at least three items; the last line is one concrete next action; no 'Great question' opener and no 'Hope this helps' closer."
---

Give me the ADHD-friendly version: how do I add JWT auth to my Express app?
