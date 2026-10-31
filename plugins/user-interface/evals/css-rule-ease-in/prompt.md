---
schema_version: "1.1"
name: css-rule-ease-in
description: "Hard (the prompt asks for motion that accelerates away): the dismissal, a permanent exit, accelerates away on the in curve or an equivalent accelerate cubic-bezier with the lag trade-off named"
tags: [always-on-rule, rule-ease-in, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The dismissal, a permanent exit, honors the explicit request for acceleration on the configured in curve or an equivalent accelerate cubic-bezier (slow start, fast end), never the bare ease-in keyword or an ease-in-out shape, and the reply warns that its slow start can read as lag"
---

Write the CSS for a toast notification that slides down and fades out when it is dismissed. It should accelerate as it leaves the screen, like it is falling away. This run cannot write files, so put the CSS in your reply.
