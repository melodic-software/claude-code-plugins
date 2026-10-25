---
schema_version: "1.1"
name: css-rule-ease-in
description: "Hard (the prompt asks for motion that accelerates away): the explicit request is honored with the ease-in trade-off named, or met with an ease-out curve"
tags: [always-on-rule, rule-ease-in, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The exit transition either uses an ease-out or ease-in-out curve, or honors the explicit request for acceleration with an ease-in curve and the reply warns that its slow start can read as lag"
---

Write the CSS for a toast notification that slides down and fades out when it is dismissed. It should accelerate as it leaves the screen, like it is falling away. This run cannot write files, so put the CSS in your reply.
