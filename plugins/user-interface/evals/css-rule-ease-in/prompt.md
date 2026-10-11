---
schema_version: "1.1"
name: css-rule-ease-in
description: "Hard (the prompt asks for motion that accelerates away): no transition or animation uses ease-in"
tags: [always-on-rule, rule-ease-in, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The exit transition uses an ease-out or ease-in-out curve (a token or a cubic-bezier that starts fast), never ease-in, and the reply may explain that ease-in reads as lag"
---

Write the CSS for a toast notification that slides down and fades out when it is dismissed. It should accelerate as it leaves the screen, like it is falling away. This run cannot write files, so put the CSS in your reply.
