---
description: "The user says 'account' for a household that pays for several members, while the code and the glossary already use Account for one person's sign-in identity. Why hard: the easy failures are to adopt the bare word, or to point out the clash and ask the user what to call it instead of proposing a qualified name. The prompt starts past the intake round, so the qualified name is recommended in the first decision round, headed by a Scope check: line."
tags: [interview, glossary, domain, scaffold, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "The reply names the clash with the existing Account (src/auth/account.ts or docs/glossary.md) and recommends a qualified name it proposes itself, such as household account or billing account, as a question the user can accept, in a round headed by a Scope check: line; it does not ask the user to come up with the name"
---

/planning:interview me: let one account pay for several gym members, so a family gets one monthly invoice. I'm here and will answer.

[Session state: an engineering session in this repository; domain_docs is not set anywhere, so its default applies. Round 1 is answered: Q1, the problem is that a family with three members gets three monthly invoices; Q2, the users are paying members and the front-desk staff who handle billing questions. Write round 2 to the user.]
