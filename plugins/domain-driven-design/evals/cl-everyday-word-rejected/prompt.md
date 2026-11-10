---
description: "An everyday word used in its ordinary sense is not admitted. glossary-contract.md Admission: a term earns an entry only when it removes ambiguity in this context (a project-specific meaning, a clash between meanings, or a rejected synonym). Hard because the word appears in the domain's own sentences, the user gives a correct definition, and a glossary exists to add it to. Needs --scaffold --allow-tools Write Edit."
tags: [domain-driven-design, ubiquitous-language, outcome, admission, hard]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply says why Week is not admitted: it is an everyday word in its ordinary sense that removes no ambiguity here. docs/glossary.md gains no Week entry, and no .md file is written or edited."
---

/domain-driven-design:ubiquitous-language Add Week to our domain glossary: seven days, Monday to Sunday. We say "orders placed this week" all the time.
