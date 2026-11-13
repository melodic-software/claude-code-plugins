---
description: "The user says 'account' for a household that pays for several members, while the code and the glossary already use Account for one person's sign-in identity. Why hard: the easy failures are to adopt the bare word, or to point out the clash and ask the user what to call it instead of proposing a qualified name."
tags: [interview, glossary, domain, scaffold]
runs: 3
max_turns: 16
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply names the clash with the existing Account (src/auth/account.ts or docs/glossary.md) and recommends a qualified name it proposes itself, such as household account or billing account, as a question the user can accept; it does not ask the user to come up with the name"
---

/planning:interview me: let one account pay for several gym members, so a family gets one monthly invoice. I'm here and will answer.

[Session state: an engineering session in this repository; domain_docs is not set anywhere, so its default applies. Nothing has been asked yet. Write your first message to the user.]
