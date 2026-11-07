---
schema_version: "1.1"
name: glossary-widow-not-orphan
description: "Hard: the two terms are often swapped, pulling toward naming the stranded top line an orphan and the wrong property."
tags: [glossary, near-synonym, hard]
runs: 5
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply names a widow, controlled by the CSS widows property, and defines an orphan as a first line stranded at the bottom"
---

When our article prints, the very last line of a paragraph sometimes lands by itself at the top of the next page. What is that called, and which CSS property deals with it?
