---
schema_version: "1.1"
name: design-bottom-sheet-motion-spokes
description: "The request matches the motion concern and the read_when of its four spokes (catalog, behaviors, gestures, performance); the design uses each in one pass."
tags: [design, motion, gesture, performance]
runs: 3
max_turns: 30
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The design reads gestures.md and performance.md with the other motion spokes, opens and closes the sheet on the drawer curve within 300ms, dismisses on a release past a velocity threshold with that velocity carried into the settle, animates only transform and opacity, and covers all three parts in one pass"
---

Design the motion for our mobile web bottom sheet: it slides up when opened, people swipe it down to dismiss, and on low-end Android phones it drops frames while it moves. This run cannot write files, so put the design in your reply.
