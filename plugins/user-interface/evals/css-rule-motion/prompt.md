---
schema_version: "1.1"
name: css-rule-motion
description: "Hard (motion is usually written unconditionally): movement transitions are opted in with prefers-reduced-motion: no-preference"
tags: [always-on-rule, rule-motion, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Transitions that move or scale (the card scale and the drawer slide) sit inside @media (prefers-reduced-motion: no-preference); opacity or color fades may stay outside; no global rule zeroes durations"
---

Write the CSS for a card that scales up slightly on hover and a side drawer that slides in from the edge when it gets an .is-open class. This run cannot write files, so put the CSS in your reply.
