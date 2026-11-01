---
tags: ['name-it-better']
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'The skill builds a structured context brief with named fields (responsibility, firing/usage context, scope boundaries, collision vocabulary, word-level blocklist with reasons — the rejected NAME itself stays out of the brief, held on the main-thread reject list, with only its abstracted rejection reason entering as a constraint), fans out ~3 fresh-context generators seeded ONLY with the brief (blind to this conversation) across the three lenses, merges and collision-checks, scores against the resolved criteria priority, and presents a ranked shortlist with a single marked RECOMMENDED pick — then stops for the human to choose.'
---

name it better — you suggested `DataManager` for the class that validates and persists orders and I don't like it.
