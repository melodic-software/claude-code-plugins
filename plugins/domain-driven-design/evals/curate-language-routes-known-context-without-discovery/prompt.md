---
tags: ['curate-language']
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
expected_outcome: 'Reads the supplied map, routes the new definition only to support-terms.md, and leaves billing-terms.md and the context boundaries unchanged. It does not duplicate the entry or run bounded-context discovery.'
---

/domain-driven-design:curate-language In the Support context, Ticket means a customer's request for help; Billing also uses ticket to mean a metered charge record. Use the supplied context map (docs/language/context-map.md) and glossaries, and record only the resolved Support meaning. Do not redesign our contexts.
