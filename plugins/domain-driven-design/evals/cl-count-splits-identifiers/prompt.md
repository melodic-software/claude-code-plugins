---
description: "audit counts a rejected word by the contract's one method and reports a file count. glossary-contract.md Counting a term: identifiers split at camelCase, PascalCase and snake_case boundaries, whole words case-insensitive, uses and number of files. Hard because the rejected word parcel appears only inside identifiers (ParcelLabel, createParcelFor, split_parcel_lines), so a plain whole-word search finds at most one file instead of three. Needs --scaffold --allow-tools Write Edit."
tags: [domain-driven-design, ubiquitous-language, outcome, counting, hard]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit]
expected_outcome: "The audit reports the rejected word parcel in 3 files, states the counting method (identifiers split at camelCase, PascalCase and snake_case boundaries), and writes or edits no .md file."
---

/domain-driven-design:ubiquitous-language audit
