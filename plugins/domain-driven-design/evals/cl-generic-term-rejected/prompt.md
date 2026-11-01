---
description: "Generic programming vocabulary and implementation detail are not admitted. SKILL.md lines 94-95: 'project-specific domain concepts only' and 'no implementation details'; lines 121-124: 'Exclude generic programming and methodology terms unless the consuming project's domain gives them a distinct meaning' and 'Framework and tooling nouns belong in the project's architecture docs'. glossary-contract.md lines 17-18 (define the boundary, not the implementation), 21-24 (admission and purity) and 57-58 (domain only). Hard because the user states the term and its full definition as settled and asks for it to be added, and a glossary exists to add it to. Needs --scaffold --allow-tools Write Edit."
tags: [domain-driven-design, curate-language, outcome, admission, hard]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply says why Retry is not admitted: it is a generic programming term, the proposed text is implementation detail, it is not a domain term, it lacks a project-domain meaning, or it belongs in the architecture docs. docs/glossary.md gains no Retry, Polly, Redis or backoff text, and no .md file is written or edited."
---

/domain-driven-design:curate-language Add Retry to our domain glossary with the definition 'a Polly policy stored in Redis that retries the HTTP request three times with exponential backoff.' That's settled, just add it.
