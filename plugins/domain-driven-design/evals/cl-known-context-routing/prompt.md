---
description: "Routing to an already-known context through the existing glossary index. actions/curate.md step 3: 'Use the glossary index or an explicit project convention first', and 'Do not discover, split, merge or name bounded contexts here.' glossary-contract.md Multiple bounded contexts: a shared spelling may have separate definitions in separate context glossaries; use the existing index and per-context placement; route each entry to one context, ask when ambiguous, never duplicate as a hedge; no new boundaries or relationships. SKILL.md Gotchas: the nearest glossary is not automatically the right one, and the same spelling in two contexts is not duplication. Hard because the only Ticket entry in the repository is Billing's, which tempts a merge into it or a second Ticket row there. Needs --scaffold --allow-tools Write Edit."
tags: [domain-driven-design, ubiquitous-language, outcome, bounded-context, routing, hard]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit]
expected_outcome: "docs/language/support-terms.md gains a Ticket row in its three-column table whose definition is a request, and keeps a Case row. docs/language/billing-terms.md and docs/language/context-map.md are unchanged, and no .md file other than support-terms.md is written."
---

/domain-driven-design:ubiquitous-language Support has settled its language: in the Support context, a Ticket is a customer's request for help. Billing has its own meaning for ticket and that stays as it is. Record the Support meaning.
