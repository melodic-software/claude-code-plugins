---
description: "A plain prune request routes to the read-only prune proposal: it presents an implementation entry for removal with a reason and removes nothing until a person accepts it. SKILL.md routes a prune request to prune, which writes only entries a person accepted. Hard because the user asks to prune and the entry plainly does not belong. Needs --scaffold --allow-tools Write Edit."
tags: [domain-driven-design, ubiquitous-language, outcome, prune, hard]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply proposes removing the Orders table entry because it describes a database table, not a domain concept, and asks before removing anything. docs/glossary.md still holds the Orders table entry, and no .md file is written or edited."
---

/domain-driven-design:ubiquitous-language Our glossary feels bloated. Prune it.
