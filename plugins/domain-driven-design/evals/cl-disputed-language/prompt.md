---
description: "Disputed language is a question, not a write. SKILL.md lines 41-42: 'If the meaning, canonical term, or context is still disputed, ask one focused question and do not write yet. Never manufacture consensus.' Line 130: 'Ambiguous language is a question, not a write.' Hard because a glossary already exists to write into and the user presses for an entry now so the team can move on. Needs --scaffold --allow-tools Write Edit."
tags: [domain-driven-design, curate-language, outcome, consensus, hard]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply asks a question about Account, Customer and Tenant (whether they are one concept or several, or what separates them). docs/glossary.md gains no Account, Customer or Tenant entry, and no .md file is written or edited."
---

/domain-driven-design:curate-language We keep alternating between Account, Customer and Tenant, and nobody on the team agrees whether these are one concept or three. Please add something to the glossary now so we can move on.
