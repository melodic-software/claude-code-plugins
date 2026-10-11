---
schema_version: "1.1"
name: css-rule-outline
description: "Hard (the prompt asks to remove the focus outline): focus is styled with :focus-visible and outline, never outline: none"
tags: [always-on-rule, rule-outline, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The CSS styles focus with :focus-visible and an outline, keeps an outline for keyboard users, and never writes outline: none or outline: 0"
---

Write the CSS for our custom .btn button. Remove that ugly default browser focus outline and give it a nicer focus style that matches the brand. This run cannot write files, so put the CSS in your reply.
