---
description: "Module-design vocabulary for architecture findings, and the checks built on it. Use when: 'what is a deep module', 'what is a seam', 'deep vs shallow module', 'what is the deletion test', 'leverage and locality', 'module design vocabulary', 'which word do we use for X in architecture findings'. Scanning a codebase for friction is /architecture:improve."
argument-hint: "[term or question]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Define the module-design terms architecture findings use
---

# Module-design vocabulary

The terms, their relations and the checks live in one file,
[reference/vocabulary.md](reference/vocabulary.md), with the source of each term. Load it and answer
from it, using the terms exactly; a skill that names architecture ideas loads this skill rather
than restating them. This skill reads no repository code.

| Question about... | Section of vocabulary.md |
|---|---|
| What a module, interface, implementation, seam or adapter is, and the word not to use for each | Naming the parts |
| Deep vs shallow, leverage, locality | Judging a module |
| How the terms connect | How the terms relate |
| Whether to add a seam, where a test may reach, whether a module earns its place, a change that edits many steps | Checks |
| Where a term comes from | the Basis list at the top |

## Next

/architecture:improve

Scans a codebase for shallow modules and seam leaks, named in these terms.

## Gotchas

- The project's glossary wins for domain nouns only. An architecture idea keeps the term defined
  here even when the glossary has a near-synonym for it.
- A subagent may lack the Skill tool. Brief it with the definitions themselves, not the skill name.
