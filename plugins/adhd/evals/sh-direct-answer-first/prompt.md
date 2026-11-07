---
description: "Legacy shape 5. A natural 'adhd style' question (no slash command; skill-fired is a with-only indicator). The first line is the verdict, not setup (rule 1); no preamble such as 'Great question' or 'Looking at your project' (rule 10); no closer or post-answer recap (rule 10). verdict-first-line needs a verdict word on the first line and refuses a first line that only echoes the question."
tags: [adhd, shape, outcome, anti-pattern, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob]
expected_outcome: "The first line gives the safety verdict on npm audit fix --force (not safe without a check, it can install breaking major versions) and the action; no preamble, no closing pleasantry, no recap."
---

adhd style. Is it safe to run `npm audit fix --force` on this project?
