---
description: "Generic programming vocabulary and implementation detail are not admitted. actions/curate.md step 4: 'project-specific domain concepts only, and no implementation details'; SKILL.md Boundaries: no general dictionary, domain only. glossary-contract.md Entry discipline (Definition, Admission, Purity) and Domain only. Hard because the user states the term and its full definition as settled and asks for it to be added, and a glossary exists to add it to. Needs --scaffold --allow-tools Write Edit."
tags: [domain-driven-design, ubiquitous-language, outcome, admission, hard]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply says why Retry is not admitted: it is a generic programming term, the proposed text is implementation detail, it is not a domain term, it lacks a project-domain meaning, or it belongs in the architecture docs. docs/glossary.md gains no Retry, Polly, Redis or backoff text, and no .md file is written or edited."
---

/domain-driven-design:ubiquitous-language Add Retry to our domain glossary with the definition 'a Polly policy stored in Redis that retries the HTTP request three times with exponential backoff.' That's settled, just add it.
