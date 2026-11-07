---
schema_version: "1.1"
name: glossary-project-name-wins
description: "Routine: the precedence rule puts the project's name first with the general term beside it."
tags: [glossary, precedence, routine]
runs: 5
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply leads with Notice, gives toast beside it as a temporary self-dismissing notification, and does not suggest renaming"
---

Our design system doc says: "Toasts are called Notices in this product. Use the Notice component for every temporary message." What's the term for the little message that pops up at the bottom and goes away on its own?
