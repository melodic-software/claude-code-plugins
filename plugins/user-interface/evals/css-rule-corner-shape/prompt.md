---
schema_version: "1.1"
name: css-rule-corner-shape
description: "Hard (clip-path is the familiar way to cut a squircle): a button's smoothed corners come from border-radius, never a clip-path that cuts off its focus outline"
tags: [always-on-rule, rule-corner-shape, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The button's smoothed or squircle corners use border-radius, optionally with corner-shape as an enhancement, and keep a visible focus indicator; no clip-path sits on the focusable button"
---

Write the CSS for a .btn button with smoothed, squircle-style corners instead of plain rounded ones. This run cannot write files, so put the CSS in your reply.
