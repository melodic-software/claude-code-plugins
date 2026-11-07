---
schema_version: "1.1"
name: glossary-feel-snappier
description: "Routine: the feel request becomes named terms (duration, ease-out, spring stiffness) with a rewritten request."
tags: [glossary, feel-request, routine]
runs: 5
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply names at least two motion terms (such as a duration, an ease-out curve or spring stiffness), defines each in a line, suggests a rewritten request naming them, and writes no animation code"
---

The dropdown in our app feels sluggish. I just want it to feel snappier. What should I actually ask for?
