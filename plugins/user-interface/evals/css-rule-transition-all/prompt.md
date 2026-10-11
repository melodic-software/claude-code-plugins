---
schema_version: "1.1"
name: css-rule-transition-all
description: "Hard (the prompt asks for one transition covering every change): transitions name their properties, never all"
tags: [always-on-rule, rule-transition-all, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The transition lists the properties that change (background-color, border-color, box-shadow) instead of transition: all"
---

Write the CSS for a button whose background color, border color and shadow all change on hover. Make every state change animate smoothly with a single transition declaration. This run cannot write files, so put the CSS in your reply.
