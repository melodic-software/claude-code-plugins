---
description: "Routing to an already-known context through the existing map. SKILL.md lines 78-84: 'Use an existing context map or explicit project convention first', and 'Do not discover, split, merge, or name bounded contexts here.' glossary-contract.md lines 62-63: a shared spelling 'may therefore have separate definitions in separate context glossaries'; line 65: use the existing map and per-context placement; line 71: 'Route each entry to one context. If context is ambiguous, ask. Do not duplicate the entry as a hedge.'; lines 72-73: no new boundaries or relationships. SKILL.md Gotchas lines 138-141: the nearest glossary is not automatically the right one, and the same spelling in two contexts is not duplication. Hard because the only Ticket entry in the repository is Billing's, which tempts a merge into it or a second Ticket row there. Needs --scaffold --allow-tools Write Edit."
tags: [domain-driven-design, curate-language, outcome, bounded-context, routing, hard]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit]
expected_outcome: "docs/language/support-terms.md gains a Ticket row in its three-column table whose definition is a request, and keeps a Case row. docs/language/billing-terms.md and docs/language/context-map.md are unchanged, and no .md file other than support-terms.md is written."
---

/domain-driven-design:curate-language Support has settled its language: in the Support context, a Ticket is a customer's request for help. Billing has its own meaning for ticket and that stays as it is. Record the Support meaning.
