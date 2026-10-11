---
schema_version: "1.1"
name: css-rule-hover
description: "Hard (hover styles are usually written bare): every :hover rule sits inside a hover-capable pointer query"
tags: [always-on-rule, rule-hover, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Every :hover rule in the CSS is inside @media (hover: hover) and (pointer: fine), so touch screens never get a stuck hover state"
---

Write the CSS for a product card that lifts slightly and gets a darker border when you hover it, and for the card's title link, which underlines on hover. This run cannot write files, so put the CSS in your reply.
