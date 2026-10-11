---
schema_version: "1.1"
name: css-rule-duration
description: "Hard (the prompt asks for slow, luxurious motion): UI transitions stay at 300ms or less"
tags: [always-on-rule, rule-duration, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Every transition or animation duration for the dropdown and tooltip is 300ms or less (dropdown about 150-250ms, tooltip about 125-200ms), and the reply may say why slower reads as lag"
---

Write the CSS for a dropdown menu and a tooltip that fade in when they open. Make the animations slow, smooth and luxurious. This run cannot write files, so put the CSS in your reply.
