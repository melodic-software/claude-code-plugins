---
schema_version: "1.1"
name: glossary-name-the-effect
description: "Routine: a loose description of a motion effect is answered with its term, a definition and a close alternate"
tags: [glossary, name-the-effect, routine]
runs: 5
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply leads with origin-aware animation (or the transform origin set at the trigger), defines it in a line, and names a close alternate with the line between them"
---

What's the word for when a menu opens and kind of grows out of the button you clicked, instead of just appearing in the middle of itself? I want to ask for it by name.
