---
description: "audit reports a code name that looks like an existing term's concept but is neither the term nor its Avoid words, and proposes it as an Avoid word through curate without writing. audit's step 5 reuses seed's grouping for the glossary's existing terms. Hard because the glossary itself has no contract defect, so a check that reads only the glossary finds nothing. Needs --scaffold --allow-tools Write Edit."
tags: [domain-driven-design, ubiquitous-language, outcome, audit, hard]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply reports PaymentDemand (src/billing/reminders.ts) as another name for Invoice and proposes recording it as an Avoid word for Invoice through curate. docs/glossary.md is unchanged, and no .md file is written or edited."
---

/domain-driven-design:ubiquitous-language audit
